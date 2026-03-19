// ============================================================================
// execute.sv — Execute stage
// ============================================================================
// Muxes ALU / MulDiv / branch-target results.
// Resolves branches (BEQ/BNE/BLT/BGE/BLTU/BGEU).
// Computes branch/jump targets.
// ============================================================================

`include "rv32_defs.svh"

module execute (
    // ── Inputs from decode/register read ────────────────────────────────
    input  logic [31:0] pc,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [31:0] imm,

    // ── ALU control ─────────────────────────────────────────────────────
    input  alu_op_t     alu_op,
    input  logic        alu_src_b_imm,   // 1 = ALU operand B is immediate

    // ── Branch / Jump ───────────────────────────────────────────────────
    input  logic        is_branch,
    input  logic        is_jal,
    input  logic        is_jalr,
    input  logic [2:0]  branch_funct3,

    // ── ALU result from ALU module ──────────────────────────────────────
    input  logic [31:0] alu_result,
    input  logic        cmp_eq,
    input  logic        cmp_lt,
    input  logic        cmp_ltu,

    // ── Outputs ─────────────────────────────────────────────────────────
    output logic [31:0] alu_a,           // operand A to ALU
    output logic [31:0] alu_b,           // operand B to ALU

    output logic [31:0] branch_target,   // computed target for taken branch/jump
    output logic        branch_taken,    // 1 = branch/jump is taken
    output logic [31:0] exe_result,      // result forwarded to MEM stage
    output logic [31:0] pc_plus_4        // return address for JAL/JALR
);

    // ── ALU operand muxing ──────────────────────────────────────────────
    // For AUIPC: A = PC, B = imm  (handled naturally — decode sets alu_src_b_imm)
    // For LUI:   decode sets ALU_PASS_B, B = imm
    // For JAL/JALR: we still compute rs1 + imm for JALR target via ALU

    assign alu_a = (is_jal || (alu_op == ALU_PASS_B && !is_jalr)) ? pc : rs1_data;
    assign alu_b = alu_src_b_imm ? imm : rs2_data;

    // ── Branch target computation ───────────────────────────────────────
    // JAL:    PC + imm_j
    // JALR:   (rs1 + imm_i) & ~1
    // Branch: PC + imm_b

    always_comb begin
        if (is_jal)
            branch_target = pc + imm;
        else if (is_jalr)
            branch_target = (rs1_data + imm) & 32'hFFFFFFFE;
        else
            branch_target = pc + imm;
    end

    // ── PC + 4 (for link register) ──────────────────────────────────────
    // Compressed instructions would be PC+2, but cpu_top handles that
    assign pc_plus_4 = pc + 32'd4;

    // ── Branch resolution ───────────────────────────────────────────────
    always_comb begin
        branch_taken = 1'b0;

        if (is_jal || is_jalr) begin
            branch_taken = 1'b1;
        end else if (is_branch) begin
            case (branch_funct3)
                `F3_BEQ:  branch_taken =  cmp_eq;
                `F3_BNE:  branch_taken = !cmp_eq;
                `F3_BLT:  branch_taken =  cmp_lt;
                `F3_BGE:  branch_taken = !cmp_lt;
                `F3_BLTU: branch_taken =  cmp_ltu;
                `F3_BGEU: branch_taken = !cmp_ltu;
                default:  branch_taken = 1'b0;
            endcase
        end
    end

    // ── Execute result ──────────────────────────────────────────────────
    assign exe_result = alu_result;

endmodule
