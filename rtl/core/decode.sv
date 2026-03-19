// ============================================================================
// decode.sv — RV32IMC instruction decoder
// ============================================================================
// Extracts fields from 32-bit instructions (after C-expansion), generates
// ALU control, immediate values, and pipeline control signals.
// Covers R/I/S/B/U/J formats + SYSTEM (CSR, ECALL, EBREAK, MRET, FENCE).
// ============================================================================

`include "rv32_defs.svh"

module decode (
    input  logic [31:0] instr,

    // ── Decoded fields ──────────────────────────────────────────────────
    output logic [4:0]  rd,
    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [31:0] imm,

    // ── ALU control ─────────────────────────────────────────────────────
    output alu_op_t     alu_op,
    output logic        alu_src_b_imm,  // 1 = ALU B input is immediate

    // ── MulDiv ──────────────────────────────────────────────────────────
    output muldiv_op_t  md_op,
    output logic        md_start,       // 1 = start muldiv operation

    // ── Memory ──────────────────────────────────────────────────────────
    output logic        mem_read,
    output logic        mem_write,
    output logic [2:0]  mem_funct3,     // byte/half/word + sign extension

    // ── Register write-back ─────────────────────────────────────────────
    output logic        reg_write,
    output wb_sel_t     wb_sel,

    // ── Branch / Jump ───────────────────────────────────────────────────
    output logic        is_branch,
    output logic        is_jal,
    output logic        is_jalr,
    output logic [2:0]  branch_funct3,

    // ── CSR ─────────────────────────────────────────────────────────────
    output logic        csr_en,
    output logic [2:0]  csr_op,         // funct3 field for CSR
    output logic [11:0] csr_addr,

    // ── Exceptions / Special ────────────────────────────────────────────
    output logic        ecall,
    output logic        ebreak,
    output logic        mret,
    output logic        fence,
    output logic        illegal_instr
);

    // ── Extract fixed fields ────────────────────────────────────────────
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [11:0] funct12;

    assign opcode  = instr[6:0];
    assign rd      = instr[11:7];
    assign rs1     = instr[19:15];
    assign rs2     = instr[24:20];
    assign funct3  = instr[14:12];
    assign funct7  = instr[31:25];
    assign funct12 = instr[31:20];

    // ── Immediate generation ────────────────────────────────────────────
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

    // I-type
    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    // S-type
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    // B-type
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    // U-type
    assign imm_u = {instr[31:12], 12'b0};
    // J-type
    assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // ── Decode logic ────────────────────────────────────────────────────
    always_comb begin
        // Defaults — everything off
        alu_op        = ALU_ADD;
        alu_src_b_imm = 1'b0;
        md_op         = MD_MUL;
        md_start      = 1'b0;
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        mem_funct3    = 3'b0;
        reg_write     = 1'b0;
        wb_sel        = WB_ALU;
        is_branch     = 1'b0;
        is_jal        = 1'b0;
        is_jalr       = 1'b0;
        branch_funct3 = 3'b0;
        csr_en        = 1'b0;
        csr_op        = 3'b0;
        csr_addr      = 12'b0;
        ecall         = 1'b0;
        ebreak        = 1'b0;
        mret          = 1'b0;
        fence         = 1'b0;
        illegal_instr = 1'b0;
        imm           = 32'b0;

        case (opcode)
            // ── LUI ─────────────────────────────────────────────────────
            `OP_LUI: begin
                imm           = imm_u;
                alu_op        = ALU_PASS_B;
                alu_src_b_imm = 1'b1;
                reg_write     = 1'b1;
                wb_sel        = WB_ALU;
            end

            // ── AUIPC ───────────────────────────────────────────────────
            `OP_AUIPC: begin
                imm           = imm_u;
                alu_op        = ALU_ADD;
                alu_src_b_imm = 1'b1;  // A input will be PC in execute stage
                reg_write     = 1'b1;
                wb_sel        = WB_ALU;
            end

            // ── JAL ─────────────────────────────────────────────────────
            `OP_JAL: begin
                imm       = imm_j;
                is_jal    = 1'b1;
                reg_write = 1'b1;
                wb_sel    = WB_PC4;
            end

            // ── JALR ────────────────────────────────────────────────────
            `OP_JALR: begin
                imm           = imm_i;
                is_jalr       = 1'b1;
                alu_op        = ALU_ADD;
                alu_src_b_imm = 1'b1;
                reg_write     = 1'b1;
                wb_sel        = WB_PC4;
            end

            // ── BRANCH ──────────────────────────────────────────────────
            `OP_BRANCH: begin
                imm           = imm_b;
                is_branch     = 1'b1;
                branch_funct3 = funct3;
            end

            // ── LOAD ────────────────────────────────────────────────────
            `OP_LOAD: begin
                imm           = imm_i;
                alu_op        = ALU_ADD;
                alu_src_b_imm = 1'b1;
                mem_read      = 1'b1;
                mem_funct3    = funct3;
                reg_write     = 1'b1;
                wb_sel        = WB_MEM;
            end

            // ── STORE ───────────────────────────────────────────────────
            `OP_STORE: begin
                imm           = imm_s;
                alu_op        = ALU_ADD;
                alu_src_b_imm = 1'b1;
                mem_write     = 1'b1;
                mem_funct3    = funct3;
            end

            // ── OP-IMM (ADDI, SLTI, etc.) ───────────────────────────────
            `OP_OP_IMM: begin
                imm           = imm_i;
                alu_src_b_imm = 1'b1;
                reg_write     = 1'b1;
                wb_sel        = WB_ALU;

                case (funct3)
                    `F3_ADD_SUB: alu_op = ALU_ADD;  // ADDI (no SUB-imm)
                    `F3_SLL:     alu_op = ALU_SLL;  // SLLI
                    `F3_SLT:     alu_op = ALU_SLT;  // SLTI
                    `F3_SLTU:    alu_op = ALU_SLTU; // SLTIU
                    `F3_XOR:     alu_op = ALU_XOR;  // XORI
                    `F3_SRL_SRA: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    `F3_OR:      alu_op = ALU_OR;   // ORI
                    `F3_AND:     alu_op = ALU_AND;  // ANDI
                    default:     illegal_instr = 1'b1;
                endcase
            end

            // ── OP (ADD, SUB, etc.) + M-extension ───────────────────────
            `OP_OP: begin
                reg_write = 1'b1;

                if (funct7 == `F7_MULDIV) begin
                    // M-extension
                    wb_sel   = WB_MULDIV;
                    md_start = 1'b1;
                    case (funct3)
                        `F3_MUL:    md_op = MD_MUL;
                        `F3_MULH:   md_op = MD_MULH;
                        `F3_MULHSU: md_op = MD_MULHSU;
                        `F3_MULHU:  md_op = MD_MULHU;
                        `F3_DIV:    md_op = MD_DIV;
                        `F3_DIVU:   md_op = MD_DIVU;
                        `F3_REM:    md_op = MD_REM;
                        `F3_REMU:   md_op = MD_REMU;
                        default:    illegal_instr = 1'b1;
                    endcase
                end else begin
                    // Base integer
                    wb_sel = WB_ALU;
                    case (funct3)
                        `F3_ADD_SUB: alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                        `F3_SLL:     alu_op = ALU_SLL;
                        `F3_SLT:     alu_op = ALU_SLT;
                        `F3_SLTU:    alu_op = ALU_SLTU;
                        `F3_XOR:     alu_op = ALU_XOR;
                        `F3_SRL_SRA: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                        `F3_OR:      alu_op = ALU_OR;
                        `F3_AND:     alu_op = ALU_AND;
                        default:     illegal_instr = 1'b1;
                    endcase
                end
            end

            // ── FENCE ───────────────────────────────────────────────────
            `OP_FENCE: begin
                fence = 1'b1;  // NOP in a single-core, in-order design
            end

            // ── SYSTEM ──────────────────────────────────────────────────
            `OP_SYSTEM: begin
                if (funct3 == 3'b000) begin
                    // ECALL / EBREAK / MRET
                    case (funct12)
                        `F12_ECALL:  ecall  = 1'b1;
                        `F12_EBREAK: ebreak = 1'b1;
                        `F12_MRET:   mret   = 1'b1;
                        default:     illegal_instr = 1'b1;
                    endcase
                end else begin
                    // CSR instructions
                    csr_en    = 1'b1;
                    csr_op    = funct3;
                    csr_addr  = instr[31:20];
                    reg_write = 1'b1;
                    wb_sel    = WB_CSR;
                    // For CSRRWI/CSRRSI/CSRRCI, rs1 field is the zimm
                    imm       = {27'b0, rs1};  // zero-extended uimm
                end
            end

            default: begin
                illegal_instr = 1'b1;
            end
        endcase
    end

endmodule
