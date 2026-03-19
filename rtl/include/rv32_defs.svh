// ============================================================================
// rv32_defs.svh — Shared definitions for the RV32IMC SoC
// ============================================================================
// Include this in every module:  `include "rv32_defs.svh"
// Vivado include path should point to rtl/include/
// ============================================================================

`ifndef RV32_DEFS_SVH
`define RV32_DEFS_SVH

// ────────────────────────────────────────────────────────────────────────────
// Data widths
// ────────────────────────────────────────────────────────────────────────────
`define XLEN        32
`define ILEN        32
`define REG_ADDR_W  5

// ────────────────────────────────────────────────────────────────────────────
// Opcodes (bits [6:0] of a 32-bit instruction)
// ────────────────────────────────────────────────────────────────────────────
`define OP_LUI       7'b0110111
`define OP_AUIPC     7'b0010111
`define OP_JAL       7'b1101111
`define OP_JALR      7'b1100111
`define OP_BRANCH    7'b1100011
`define OP_LOAD      7'b0000011
`define OP_STORE     7'b0100011
`define OP_OP_IMM    7'b0010011
`define OP_OP        7'b0110011
`define OP_FENCE     7'b0001111
`define OP_SYSTEM    7'b1110011

// ────────────────────────────────────────────────────────────────────────────
// funct3 — Branch
// ────────────────────────────────────────────────────────────────────────────
`define F3_BEQ   3'b000
`define F3_BNE   3'b001
`define F3_BLT   3'b100
`define F3_BGE   3'b101
`define F3_BLTU  3'b110
`define F3_BGEU  3'b111

// ────────────────────────────────────────────────────────────────────────────
// funct3 — Load / Store
// ────────────────────────────────────────────────────────────────────────────
`define F3_BYTE   3'b000
`define F3_HALF   3'b001
`define F3_WORD   3'b010
`define F3_BYTEU  3'b100
`define F3_HALFU  3'b101

// ────────────────────────────────────────────────────────────────────────────
// funct3 — ALU (OP / OP-IMM)
// ────────────────────────────────────────────────────────────────────────────
`define F3_ADD_SUB  3'b000
`define F3_SLL      3'b001
`define F3_SLT      3'b010
`define F3_SLTU     3'b011
`define F3_XOR      3'b100
`define F3_SRL_SRA  3'b101
`define F3_OR       3'b110
`define F3_AND      3'b111

// ────────────────────────────────────────────────────────────────────────────
// funct3 — M-extension
// ────────────────────────────────────────────────────────────────────────────
`define F3_MUL      3'b000
`define F3_MULH     3'b001
`define F3_MULHSU   3'b010
`define F3_MULHU    3'b011
`define F3_DIV      3'b100
`define F3_DIVU     3'b101
`define F3_REM      3'b110
`define F3_REMU     3'b111

`define F7_MULDIV   7'b0000001

// ────────────────────────────────────────────────────────────────────────────
// funct3 — CSR
// ────────────────────────────────────────────────────────────────────────────
`define F3_CSRRW   3'b001
`define F3_CSRRS   3'b010
`define F3_CSRRC   3'b011
`define F3_CSRRWI  3'b101
`define F3_CSRRSI  3'b110
`define F3_CSRRCI  3'b111

// ────────────────────────────────────────────────────────────────────────────
// funct12 — SYSTEM special
// ────────────────────────────────────────────────────────────────────────────
`define F12_ECALL   12'b000000000000
`define F12_EBREAK  12'b000000000001
`define F12_MRET    12'b001100000010

// ────────────────────────────────────────────────────────────────────────────
// ALU operation select (internal encoding)
// ────────────────────────────────────────────────────────────────────────────
typedef enum logic [3:0] {
    ALU_ADD    = 4'd0,
    ALU_SUB    = 4'd1,
    ALU_AND    = 4'd2,
    ALU_OR     = 4'd3,
    ALU_XOR    = 4'd4,
    ALU_SLL    = 4'd5,
    ALU_SRL    = 4'd6,
    ALU_SRA    = 4'd7,
    ALU_SLT    = 4'd8,
    ALU_SLTU   = 4'd9,
    ALU_PASS_B = 4'd10
} alu_op_t;

// ────────────────────────────────────────────────────────────────────────────
// MulDiv operation select
// ────────────────────────────────────────────────────────────────────────────
typedef enum logic [2:0] {
    MD_MUL    = 3'd0,
    MD_MULH   = 3'd1,
    MD_MULHSU = 3'd2,
    MD_MULHU  = 3'd3,
    MD_DIV    = 3'd4,
    MD_DIVU   = 3'd5,
    MD_REM    = 3'd6,
    MD_REMU   = 3'd7
} muldiv_op_t;

// ────────────────────────────────────────────────────────────────────────────
// Writeback source select
// ────────────────────────────────────────────────────────────────────────────
typedef enum logic [2:0] {
    WB_ALU    = 3'd0,
    WB_MEM    = 3'd1,
    WB_PC4    = 3'd2,
    WB_CSR    = 3'd3,
    WB_MULDIV = 3'd4
} wb_sel_t;

// ────────────────────────────────────────────────────────────────────────────
// CSR addresses (Machine-mode)
// ────────────────────────────────────────────────────────────────────────────
`define CSR_MSTATUS   12'h300
`define CSR_MISA      12'h301
`define CSR_MIE       12'h304
`define CSR_MTVEC     12'h305
`define CSR_MSCRATCH  12'h340
`define CSR_MEPC      12'h341
`define CSR_MCAUSE    12'h342
`define CSR_MTVAL     12'h343
`define CSR_MIP       12'h344
`define CSR_MCYCLE    12'hB00
`define CSR_MINSTRET  12'hB02
`define CSR_MCYCLEH   12'hB80
`define CSR_MINSTRETH 12'hB82
`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID   12'hF12
`define CSR_MIMPID    12'hF13
`define CSR_MHARTID   12'hF14

// ────────────────────────────────────────────────────────────────────────────
// Exception / interrupt cause codes (mcause)
// ────────────────────────────────────────────────────────────────────────────
`define EXC_INSTR_MISALIGN  32'd0
`define EXC_ILLEGAL_INSTR   32'd2
`define EXC_BREAKPOINT      32'd3
`define EXC_LOAD_MISALIGN   32'd4
`define EXC_STORE_MISALIGN  32'd6
`define EXC_ECALL_M         32'd11

`define INT_MSI   {1'b1, 31'd3}
`define INT_MTI   {1'b1, 31'd7}
`define INT_MEI   {1'b1, 31'd11}

`endif // RV32_DEFS_SVH
