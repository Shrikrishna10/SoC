// ============================================================================
// cpu_top.sv — RV32IMC 5-stage pipelined CPU top-level
// ============================================================================
// Wires: Fetch → Decode → Execute → Memory → Writeback
// Pipeline registers between stages, stall/flush control.
// Exposes two TL-UL interfaces: instruction bus + data bus.
// ============================================================================

`include "rv32_defs.svh"
`include "tl_ul_defs.svh"

module cpu_top (
    input  logic        clk,
    input  logic        rst_n,

    // ── Instruction bus (TL-UL) ─────────────────────────────────────────
    output tl_h2d_t     imem_h2d,
    input  tl_d2h_t     imem_d2h,

    // ── Data bus (TL-UL) ────────────────────────────────────────────────
    output tl_h2d_t     dmem_h2d,
    input  tl_d2h_t     dmem_d2h,

    // ── External interrupts ─────────────────────────────────────────────
    input  logic        ext_irq,
    input  logic        timer_irq,
    input  logic        sw_irq
);

    // ====================================================================
    // Pipeline signals
    // ====================================================================

    // ── Fetch outputs ───────────────────────────────────────────────────
    logic [31:0] f_pc, f_instr;
    logic        f_valid;

    // ── IF/ID pipeline register ─────────────────────────────────────────
    logic [31:0] id_pc, id_instr;
    logic        id_valid;

    // ── Compressed decoder outputs ──────────────────────────────────────
    logic [31:0] id_instr_expanded;
    logic        id_is_compressed;
    logic        id_illegal_c;

    // ── Decode outputs ──────────────────────────────────────────────────
    logic [4:0]  id_rd, id_rs1, id_rs2;
    logic [31:0] id_imm;
    alu_op_t     id_alu_op;
    logic        id_alu_src_b_imm;
    muldiv_op_t  id_md_op;
    logic        id_md_start;
    logic        id_mem_read, id_mem_write;
    logic [2:0]  id_mem_funct3;
    logic        id_reg_write;
    wb_sel_t     id_wb_sel;
    logic        id_is_branch, id_is_jal, id_is_jalr;
    logic [2:0]  id_branch_funct3;
    logic        id_csr_en;
    logic [2:0]  id_csr_op;
    logic [11:0] id_csr_addr;
    logic        id_ecall, id_ebreak, id_mret, id_fence;
    logic        id_illegal_instr;

    // ── Register file outputs ───────────────────────────────────────────
    logic [31:0] id_rs1_data, id_rs2_data;

    // ── ID/EX pipeline register ─────────────────────────────────────────
    logic [31:0] ex_pc;
    logic [31:0] ex_rs1_data, ex_rs2_data, ex_imm;
    logic [4:0]  ex_rd, ex_rs1, ex_rs2;
    alu_op_t     ex_alu_op;
    logic        ex_alu_src_b_imm;
    muldiv_op_t  ex_md_op;
    logic        ex_md_start;
    logic        ex_mem_read, ex_mem_write;
    logic [2:0]  ex_mem_funct3;
    logic        ex_reg_write;
    wb_sel_t     ex_wb_sel;
    logic        ex_is_branch, ex_is_jal, ex_is_jalr;
    logic [2:0]  ex_branch_funct3;
    logic        ex_csr_en;
    logic [2:0]  ex_csr_op;
    logic [11:0] ex_csr_addr;
    logic        ex_ecall, ex_ebreak, ex_mret;
    logic        ex_illegal_instr;
    logic        ex_is_compressed;
    logic        ex_valid;

    // ── Execute stage outputs ───────────────────────────────────────────
    logic [31:0] ex_alu_a, ex_alu_b, ex_alu_result;
    logic        ex_cmp_eq, ex_cmp_lt, ex_cmp_ltu;
    logic [31:0] ex_branch_target, ex_exe_result, ex_pc_plus_n;
    logic        ex_branch_taken;

    // ── EX/MEM pipeline register ────────────────────────────────────────
    logic [31:0] mem_alu_result, mem_rs2_data, mem_pc_plus_n;
    logic [4:0]  mem_rd;
    logic        mem_mem_read, mem_mem_write;
    logic [2:0]  mem_mem_funct3;
    logic        mem_reg_write;
    wb_sel_t     mem_wb_sel;
    logic [31:0] mem_csr_rdata;
    logic [31:0] mem_muldiv_result;
    logic        mem_valid;

    // ── Memory stage outputs ────────────────────────────────────────────
    logic [31:0] mem_load_data;
    logic        mem_busy;

    // ── MEM/WB pipeline register ────────────────────────────────────────
    logic [31:0] wb_alu_result, wb_load_data, wb_pc_plus_n;
    logic [31:0] wb_csr_rdata, wb_muldiv_result;
    logic [4:0]  wb_rd;
    logic        wb_reg_write;
    wb_sel_t     wb_wb_sel;

    // ── Writeback output ────────────────────────────────────────────────
    logic [31:0] wb_data;

    // ── MulDiv signals ──────────────────────────────────────────────────
    logic [31:0] md_result;
    logic        md_busy, md_valid;

    // ── CSR signals ─────────────────────────────────────────────────────
    logic [31:0] csr_rdata, csr_wdata;
    logic        trap_taken, mret_out;
    logic [31:0] trap_vector, mepc_out;

    // ── Stall / Flush ───────────────────────────────────────────────────
    logic stall, flush;

    // Stall: muldiv busy or memory not ready
    assign stall = md_busy || mem_busy;

    // Flush: branch/jump taken or trap/mret
    assign flush = ex_branch_taken || trap_taken || mret_out;

    // ====================================================================
    // Fetch Stage
    // ====================================================================
    logic [31:0] redirect_pc;

    always_comb begin
        if (trap_taken)
            redirect_pc = trap_vector;
        else if (mret_out)
            redirect_pc = mepc_out;
        else
            redirect_pc = ex_branch_target;
    end

    fetch u_fetch (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (stall),
        .flush          (flush),
        .branch_target  (redirect_pc),
        .pc_o           (f_pc),
        .instr_o        (f_instr),
        .valid_o        (f_valid),
        .imem_h2d       (imem_h2d),
        .imem_d2h       (imem_d2h)
    );

    // ====================================================================
    // IF/ID Pipeline Register
    // ====================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc    <= 32'b0;
            id_instr <= 32'h0000_0013; // NOP = addi x0, x0, 0
            id_valid <= 1'b0;
        end else if (flush) begin
            id_instr <= 32'h0000_0013;
            id_valid <= 1'b0;
        end else if (!stall) begin
            id_pc    <= f_pc;
            id_instr <= f_instr;
            id_valid <= f_valid;
        end
    end

    // ====================================================================
    // Compressed Decoder
    // ====================================================================
    compressed_decoder u_cdec (
        .instr_i       (id_instr),
        .instr_o       (id_instr_expanded),
        .is_compressed (id_is_compressed),
        .illegal_c     (id_illegal_c)
    );

    // ====================================================================
    // Decode
    // ====================================================================
    decode u_decode (
        .instr         (id_instr_expanded),
        .rd            (id_rd),
        .rs1           (id_rs1),
        .rs2           (id_rs2),
        .imm           (id_imm),
        .alu_op        (id_alu_op),
        .alu_src_b_imm (id_alu_src_b_imm),
        .md_op         (id_md_op),
        .md_start      (id_md_start),
        .mem_read      (id_mem_read),
        .mem_write     (id_mem_write),
        .mem_funct3    (id_mem_funct3),
        .reg_write     (id_reg_write),
        .wb_sel        (id_wb_sel),
        .is_branch     (id_is_branch),
        .is_jal        (id_is_jal),
        .is_jalr       (id_is_jalr),
        .branch_funct3 (id_branch_funct3),
        .csr_en        (id_csr_en),
        .csr_op        (id_csr_op),
        .csr_addr      (id_csr_addr),
        .ecall         (id_ecall),
        .ebreak        (id_ebreak),
        .mret          (id_mret),
        .fence         (id_fence),
        .illegal_instr (id_illegal_instr)
    );

    // ====================================================================
    // Register File
    // ====================================================================
    regfile u_regfile (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_en      (wb_reg_write),
        .wr_addr    (wb_rd),
        .wr_data    (wb_data),
        .rd_addr_a  (id_rs1),
        .rd_data_a  (id_rs1_data),
        .rd_addr_b  (id_rs2),
        .rd_data_b  (id_rs2_data)
    );

    // ====================================================================
    // ID/EX Pipeline Register
    // ====================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            ex_pc            <= 32'b0;
            ex_rs1_data      <= 32'b0;
            ex_rs2_data      <= 32'b0;
            ex_imm           <= 32'b0;
            ex_rd            <= 5'b0;
            ex_rs1           <= 5'b0;
            ex_rs2           <= 5'b0;
            ex_alu_op        <= ALU_ADD;
            ex_alu_src_b_imm <= 1'b0;
            ex_md_op         <= MD_MUL;
            ex_md_start      <= 1'b0;
            ex_mem_read      <= 1'b0;
            ex_mem_write     <= 1'b0;
            ex_mem_funct3    <= 3'b0;
            ex_reg_write     <= 1'b0;
            ex_wb_sel        <= WB_ALU;
            ex_is_branch     <= 1'b0;
            ex_is_jal        <= 1'b0;
            ex_is_jalr       <= 1'b0;
            ex_branch_funct3 <= 3'b0;
            ex_csr_en        <= 1'b0;
            ex_csr_op        <= 3'b0;
            ex_csr_addr      <= 12'b0;
            ex_ecall         <= 1'b0;
            ex_ebreak        <= 1'b0;
            ex_mret          <= 1'b0;
            ex_illegal_instr <= 1'b0;
            ex_is_compressed <= 1'b0;
            ex_valid         <= 1'b0;
        end else if (!stall) begin
            ex_pc            <= id_pc;
            ex_rs1_data      <= id_rs1_data;
            ex_rs2_data      <= id_rs2_data;
            ex_imm           <= id_imm;
            ex_rd            <= id_rd;
            ex_rs1           <= id_rs1;
            ex_rs2           <= id_rs2;
            ex_alu_op        <= id_alu_op;
            ex_alu_src_b_imm <= id_alu_src_b_imm;
            ex_md_op         <= id_md_op;
            ex_md_start      <= id_md_start && id_valid;
            ex_mem_read      <= id_mem_read;
            ex_mem_write     <= id_mem_write;
            ex_mem_funct3    <= id_mem_funct3;
            ex_reg_write     <= id_reg_write;
            ex_wb_sel        <= id_wb_sel;
            ex_is_branch     <= id_is_branch;
            ex_is_jal        <= id_is_jal;
            ex_is_jalr       <= id_is_jalr;
            ex_branch_funct3 <= id_branch_funct3;
            ex_csr_en        <= id_csr_en;
            ex_csr_op        <= id_csr_op;
            ex_csr_addr      <= id_csr_addr;
            ex_ecall         <= id_ecall;
            ex_ebreak        <= id_ebreak;
            ex_mret          <= id_mret;
            ex_illegal_instr <= id_illegal_instr || id_illegal_c;
            ex_is_compressed <= id_is_compressed;
            ex_valid         <= id_valid;
        end
    end

    // ====================================================================
    // ALU instance
    // ====================================================================
    alu u_alu (
        .a       (ex_alu_a),
        .b       (ex_alu_b),
        .op      (ex_alu_op),
        .result  (ex_alu_result),
        .cmp_eq  (ex_cmp_eq),
        .cmp_lt  (ex_cmp_lt),
        .cmp_ltu (ex_cmp_ltu)
    );

    // ====================================================================
    // Execute Stage
    // ====================================================================
    execute u_execute (
        .pc              (ex_pc),
        .rs1_data        (ex_rs1_data),
        .rs2_data        (ex_rs2_data),
        .imm             (ex_imm),
        .alu_op          (ex_alu_op),
        .alu_src_b_imm   (ex_alu_src_b_imm),
        .is_branch       (ex_is_branch),
        .is_jal          (ex_is_jal),
        .is_jalr         (ex_is_jalr),
        .branch_funct3   (ex_branch_funct3),
        .alu_result      (ex_alu_result),
        .cmp_eq          (ex_cmp_eq),
        .cmp_lt          (ex_cmp_lt),
        .cmp_ltu         (ex_cmp_ltu),
        .alu_a           (ex_alu_a),
        .alu_b           (ex_alu_b),
        .branch_target   (ex_branch_target),
        .branch_taken    (ex_branch_taken),
        .exe_result      (ex_exe_result),
        .pc_plus_4       (ex_pc_plus_n)
    );

    // Adjust PC+N for compressed instructions (PC+2 instead of PC+4)
    logic [31:0] ex_link_addr;
    assign ex_link_addr = ex_is_compressed ? (ex_pc + 32'd2) : ex_pc_plus_n;

    // ====================================================================
    // MulDiv
    // ====================================================================
    muldiv u_muldiv (
        .clk       (clk),
        .rst_n     (rst_n),
        .operand_a (ex_rs1_data),
        .operand_b (ex_rs2_data),
        .op        (ex_md_op),
        .start     (ex_md_start && ex_valid && !flush),
        .result    (md_result),
        .busy      (md_busy),
        .valid     (md_valid)
    );

    // ====================================================================
    // CSR
    // ====================================================================
    // CSR write data: for CSRRW/S/C use rs1, for I-variants use zero-extended uimm
    assign csr_wdata = (ex_csr_op[2]) ? {27'b0, ex_rs1} : ex_rs1_data;

    csr u_csr (
        .clk            (clk),
        .rst_n          (rst_n),
        .csr_en         (ex_csr_en && ex_valid),
        .csr_op         (ex_csr_op),
        .csr_addr       (ex_csr_addr),
        .csr_wdata      (csr_wdata),
        .csr_rdata      (csr_rdata),
        .ecall          (ex_ecall && ex_valid),
        .ebreak         (ex_ebreak && ex_valid),
        .mret_i         (ex_mret && ex_valid),
        .illegal_instr  (ex_illegal_instr && ex_valid),
        .trap_pc        (ex_pc),
        .trap_val       (id_instr_expanded),
        .instr_retired  (wb_reg_write || mem_mem_write),  // rough retire signal
        .ext_irq        (ext_irq),
        .timer_irq      (timer_irq),
        .sw_irq         (sw_irq),
        .trap_taken     (trap_taken),
        .mret_o         (mret_out),
        .trap_vector    (trap_vector),
        .mepc_o         (mepc_out)
    );

    // ====================================================================
    // EX/MEM Pipeline Register
    // ====================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            mem_alu_result    <= 32'b0;
            mem_rs2_data      <= 32'b0;
            mem_pc_plus_n     <= 32'b0;
            mem_rd            <= 5'b0;
            mem_mem_read      <= 1'b0;
            mem_mem_write     <= 1'b0;
            mem_mem_funct3    <= 3'b0;
            mem_reg_write     <= 1'b0;
            mem_wb_sel        <= WB_ALU;
            mem_csr_rdata     <= 32'b0;
            mem_muldiv_result <= 32'b0;
            mem_valid         <= 1'b0;
        end else if (!stall) begin
            mem_alu_result    <= ex_exe_result;
            mem_rs2_data      <= ex_rs2_data;
            mem_pc_plus_n     <= ex_link_addr;
            mem_rd            <= ex_rd;
            mem_mem_read      <= ex_mem_read;
            mem_mem_write     <= ex_mem_write;
            mem_mem_funct3    <= ex_mem_funct3;
            mem_reg_write     <= ex_reg_write;
            mem_wb_sel        <= ex_wb_sel;
            mem_csr_rdata     <= csr_rdata;
            mem_muldiv_result <= md_result;
            mem_valid         <= ex_valid;
        end
    end

    // ====================================================================
    // Memory Stage
    // ====================================================================
    mem_stage u_mem_stage (
        .mem_read   (mem_mem_read && mem_valid),
        .mem_write  (mem_mem_write && mem_valid),
        .mem_funct3 (mem_mem_funct3),
        .addr       (mem_alu_result),
        .store_data (mem_rs2_data),
        .dmem_h2d   (dmem_h2d),
        .dmem_d2h   (dmem_d2h),
        .load_data  (mem_load_data),
        .mem_busy   (mem_busy)
    );

    // ====================================================================
    // MEM/WB Pipeline Register
    // ====================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_alu_result    <= 32'b0;
            wb_load_data     <= 32'b0;
            wb_pc_plus_n     <= 32'b0;
            wb_csr_rdata     <= 32'b0;
            wb_muldiv_result <= 32'b0;
            wb_rd            <= 5'b0;
            wb_reg_write     <= 1'b0;
            wb_wb_sel        <= WB_ALU;
        end else if (!stall) begin
            wb_alu_result    <= mem_alu_result;
            wb_load_data     <= mem_load_data;
            wb_pc_plus_n     <= mem_pc_plus_n;
            wb_csr_rdata     <= mem_csr_rdata;
            wb_muldiv_result <= mem_muldiv_result;
            wb_rd            <= mem_rd;
            wb_reg_write     <= mem_reg_write && mem_valid;
            wb_wb_sel        <= mem_wb_sel;
        end
    end

    // ====================================================================
    // Writeback
    // ====================================================================
    writeback u_writeback (
        .wb_sel         (wb_wb_sel),
        .alu_result     (wb_alu_result),
        .mem_data       (wb_load_data),
        .pc_plus_4      (wb_pc_plus_n),
        .csr_rdata      (wb_csr_rdata),
        .muldiv_result  (wb_muldiv_result),
        .wb_data        (wb_data)
    );

endmodule
