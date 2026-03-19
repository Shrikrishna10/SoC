// ============================================================================
// alu.sv — RV32I ALU
// ============================================================================
// Pure combinational. No operator overloading — uses explicit bitwise ops
// and the '+'/'-' primitives (Vivado maps these to fast carry-chain adders).
//
// Outputs: result + branch comparison flags.
// ============================================================================

`include "rv32_defs.svh"

module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  alu_op_t     op,

    output logic [31:0] result,

    // Branch comparison outputs
    output logic        cmp_eq,     // a == b
    output logic        cmp_lt,     // signed(a) < signed(b)
    output logic        cmp_ltu     // unsigned(a) < unsigned(b)
);

    // ── Subtraction for comparisons ──────────────────────────────────────
    logic [32:0] sub_result;  // 33-bit to capture borrow
    assign sub_result = {1'b0, a} + {1'b0, ~b} + 33'd1;

    // ── Branch comparison flags ──────────────────────────────────────────
    assign cmp_eq  = (a == b);
    assign cmp_ltu = sub_result[32];  // borrow = unsigned less-than

    // Signed less-than: overflow-aware
    // If signs differ: a is negative => a < b
    // If signs same:   subtraction result sign gives the answer
    assign cmp_lt = (a[31] ^ b[31]) ? a[31] : sub_result[31];

    // ── Main ALU mux ────────────────────────────────────────────────────
    always_comb begin
        case (op)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = sub_result[31:0];
            ALU_AND:    result = a & b;
            ALU_OR:     result = a | b;
            ALU_XOR:    result = a ^ b;
            ALU_SLL:    result = a << b[4:0];
            ALU_SRL:    result = a >> b[4:0];
            ALU_SRA:    result = $signed(a) >>> b[4:0];
            ALU_SLT:    result = {31'b0, cmp_lt};
            ALU_SLTU:   result = {31'b0, cmp_ltu};
            ALU_PASS_B: result = b;
            default:    result = 32'b0;
        endcase
    end

endmodule
