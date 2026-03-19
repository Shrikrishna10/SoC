// ============================================================================
// csr.sv — Machine-mode CSR unit
// ============================================================================
// Implements the RV32 Machine-mode privilege registers:
//   mstatus, misa, mie, mtvec, mscratch, mepc, mcause, mtval, mip
//   mcycle/mcycleh, minstret/minstreth (read-only counters)
//   mvendorid, marchid, mimpid, mhartid (read-only ID)
//
// CSR instructions: CSRRW/S/C and immediate variants.
// Trap handling: ECALL, EBREAK, MRET, illegal instruction, interrupts.
// ============================================================================

`include "rv32_defs.svh"

module csr (
    input  logic        clk,
    input  logic        rst_n,

    // ── CSR instruction interface ───────────────────────────────────────
    input  logic        csr_en,
    input  logic [2:0]  csr_op,         // funct3: CSRRW/S/C/WI/SI/CI
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,      // rs1 value or zero-extended uimm
    output logic [31:0] csr_rdata,      // read value (old CSR value)

    // ── Trap sources ────────────────────────────────────────────────────
    input  logic        ecall,
    input  logic        ebreak,
    input  logic        mret_i,
    input  logic        illegal_instr,
    input  logic [31:0] trap_pc,        // PC of faulting/system instruction
    input  logic [31:0] trap_val,       // mtval (faulting instruction or addr)

    // ── Instruction retire (for minstret) ───────────────────────────────
    input  logic        instr_retired,

    // ── External interrupts ─────────────────────────────────────────────
    input  logic        ext_irq,        // from PLIC
    input  logic        timer_irq,      // from CLINT
    input  logic        sw_irq,         // from CLINT msip

    // ── Outputs to pipeline ─────────────────────────────────────────────
    output logic        trap_taken,     // redirect PC to mtvec
    output logic        mret_o,         // redirect PC to mepc
    output logic [31:0] trap_vector,    // mtvec value
    output logic [31:0] mepc_o          // mepc value (for MRET)
);

    // ── CSR registers ───────────────────────────────────────────────────
    logic [31:0] mstatus;
    logic [31:0] mie;
    logic [31:0] mtvec;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;
    logic [31:0] mip;

    // 64-bit counters split into 32-bit halves
    logic [63:0] mcycle;
    logic [63:0] minstret;

    // mstatus fields (simplified, machine-mode only)
    // mstatus[3]  = MIE  (machine interrupt enable)
    // mstatus[7]  = MPIE (previous MIE)
    // mstatus[12:11] = MPP (previous privilege, always 2'b11 for M-mode)

    // ── misa: constant ──────────────────────────────────────────────────
    // RV32IMC: bits I(8)=1, M(12)=1, C(2)=1, MXL=01 (32-bit)
    localparam logic [31:0] MISA = {2'b01, 4'b0, 26'b00_0000_0001_0000_0000_0000_0100};

    // ── Read mux ────────────────────────────────────────────────────────
    always_comb begin
        csr_rdata = 32'b0;
        case (csr_addr)
            `CSR_MSTATUS:   csr_rdata = mstatus;
            `CSR_MISA:      csr_rdata = MISA;
            `CSR_MIE:       csr_rdata = mie;
            `CSR_MTVEC:     csr_rdata = mtvec;
            `CSR_MSCRATCH:  csr_rdata = mscratch;
            `CSR_MEPC:      csr_rdata = mepc;
            `CSR_MCAUSE:    csr_rdata = mcause;
            `CSR_MTVAL:     csr_rdata = mtval;
            `CSR_MIP:       csr_rdata = mip;
            `CSR_MCYCLE:    csr_rdata = mcycle[31:0];
            `CSR_MCYCLEH:   csr_rdata = mcycle[63:32];
            `CSR_MINSTRET:  csr_rdata = minstret[31:0];
            `CSR_MINSTRETH: csr_rdata = minstret[63:32];
            `CSR_MVENDORID: csr_rdata = 32'b0;
            `CSR_MARCHID:   csr_rdata = 32'b0;
            `CSR_MIMPID:    csr_rdata = 32'b0;
            `CSR_MHARTID:   csr_rdata = 32'b0;
            default:        csr_rdata = 32'b0;
        endcase
    end

    // ── CSR write value computation ─────────────────────────────────────
    logic [31:0] csr_write_val;

    always_comb begin
        case (csr_op)
            `F3_CSRRW, `F3_CSRRWI: csr_write_val = csr_wdata;
            `F3_CSRRS, `F3_CSRRSI: csr_write_val = csr_rdata | csr_wdata;
            `F3_CSRRC, `F3_CSRRCI: csr_write_val = csr_rdata & (~csr_wdata);
            default:                csr_write_val = csr_rdata;
        endcase
    end

    // ── Interrupt pending (mip) ─────────────────────────────────────────
    // mip is partly read-only (external sources drive the bits)
    always_comb begin
        mip        = 32'b0;
        mip[3]     = sw_irq;     // MSIP
        mip[7]     = timer_irq;  // MTIP
        mip[11]    = ext_irq;    // MEIP
    end

    // ── Interrupt arbitration ───────────────────────────────────────────
    logic irq_pending;
    logic [31:0] irq_cause;

    always_comb begin
        irq_pending = 1'b0;
        irq_cause   = 32'b0;

        // Interrupts only taken if MIE is set
        if (mstatus[3]) begin
            // Priority: MEI > MSI > MTI
            if (mip[11] && mie[11]) begin
                irq_pending = 1'b1;
                irq_cause   = `INT_MEI;
            end else if (mip[3] && mie[3]) begin
                irq_pending = 1'b1;
                irq_cause   = `INT_MSI;
            end else if (mip[7] && mie[7]) begin
                irq_pending = 1'b1;
                irq_cause   = `INT_MTI;
            end
        end
    end

    // ── Trap detection ──────────────────────────────────────────────────
    logic exception;
    logic [31:0] exc_cause;

    always_comb begin
        exception = 1'b0;
        exc_cause = 32'b0;

        if (illegal_instr) begin
            exception = 1'b1;
            exc_cause = `EXC_ILLEGAL_INSTR;
        end else if (ecall) begin
            exception = 1'b1;
            exc_cause = `EXC_ECALL_M;
        end else if (ebreak) begin
            exception = 1'b1;
            exc_cause = `EXC_BREAKPOINT;
        end
    end

    assign trap_taken  = exception || irq_pending;
    assign mret_o      = mret_i;
    assign trap_vector = mtvec;
    assign mepc_o      = mepc;

    // ── Sequential update ───────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus  <= 32'h0000_1800;  // MPP = M-mode (2'b11)
            mie      <= 32'b0;
            mtvec    <= 32'b0;
            mscratch <= 32'b0;
            mepc     <= 32'b0;
            mcause   <= 32'b0;
            mtval    <= 32'b0;
            mcycle   <= 64'b0;
            minstret <= 64'b0;
        end else begin
            // ── Cycle counter always increments ─────────────────────
            mcycle <= mcycle + 64'd1;

            // ── Instruction retire counter ──────────────────────────
            if (instr_retired)
                minstret <= minstret + 64'd1;

            // ── Trap entry ──────────────────────────────────────────
            if (trap_taken) begin
                mepc            <= trap_pc;
                mstatus[7]      <= mstatus[3];   // MPIE = MIE
                mstatus[3]      <= 1'b0;          // MIE = 0 (disable interrupts)
                mstatus[12:11]  <= 2'b11;         // MPP = M

                if (exception) begin
                    mcause <= exc_cause;
                    mtval  <= trap_val;
                end else begin
                    mcause <= irq_cause;
                    mtval  <= 32'b0;
                end
            end

            // ── MRET ────────────────────────────────────────────────
            else if (mret_i) begin
                mstatus[3]     <= mstatus[7];    // MIE = MPIE
                mstatus[7]     <= 1'b1;          // MPIE = 1
                mstatus[12:11] <= 2'b11;         // MPP = M
            end

            // ── CSR writes ──────────────────────────────────────────
            else if (csr_en) begin
                case (csr_addr)
                    `CSR_MSTATUS:  mstatus  <= csr_write_val & 32'h0000_1888; // mask writable bits
                    `CSR_MIE:      mie      <= csr_write_val;
                    `CSR_MTVEC:    mtvec    <= {csr_write_val[31:2], 2'b00}; // force aligned
                    `CSR_MSCRATCH: mscratch <= csr_write_val;
                    `CSR_MEPC:     mepc     <= {csr_write_val[31:1], 1'b0};  // force aligned
                    `CSR_MCAUSE:   mcause   <= csr_write_val;
                    `CSR_MTVAL:    mtval    <= csr_write_val;
                    // mcycle, minstret, misa, mvendorid etc. are read-only
                    default: ;
                endcase
            end
        end
    end

endmodule
