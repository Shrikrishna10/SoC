// ============================================================================
// fetch.sv — Instruction Fetch stage
// ============================================================================
// Maintains the PC register, issues TL-UL reads to instruction memory,
// handles branch/jump redirects and pipeline stalls.
// Supports both 16-bit (compressed) and 32-bit instructions.
// ============================================================================

`include "rv32_defs.svh"
`include "tl_ul_defs.svh"

module fetch (
    input  logic        clk,
    input  logic        rst_n,

    // ── Pipeline control ────────────────────────────────────────────────
    input  logic        stall,          // hold PC (e.g. muldiv busy, load)
    input  logic        flush,          // branch/jump taken
    input  logic [31:0] branch_target,  // redirect PC

    // ── Output to Decode stage ──────────────────────────────────────────
    output logic [31:0] pc_o,           // current PC
    output logic [31:0] instr_o,        // fetched instruction (may be 16-bit)
    output logic        valid_o,        // instruction is valid this cycle

    // ── TL-UL instruction bus (host side) ───────────────────────────────
    output tl_h2d_t     imem_h2d,
    input  tl_d2h_t     imem_d2h
);

    // Boot address — matches implementation plan
    localparam logic [31:0] RESET_VECTOR = 32'h0000_1000;

    // ── PC register ─────────────────────────────────────────────────────
    logic [31:0] pc_r, pc_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_r <= RESET_VECTOR;
        else if (!stall)
            pc_r <= pc_next;
    end

    // ── Next PC logic ───────────────────────────────────────────────────
    // Compressed instructions advance by 2, normal by 4
    logic is_compressed_instr;
    assign is_compressed_instr = (imem_d2h.rdata[1:0] != 2'b11);

    always_comb begin
        if (flush)
            pc_next = branch_target;
        else if (is_compressed_instr && imem_d2h.valid)
            pc_next = pc_r + 32'd2;
        else
            pc_next = pc_r + 32'd4;
    end

    // ── Drive TL-UL instruction memory request ─────────────────────────
    // Always reading (never writing) instruction memory
    assign imem_h2d.valid = !stall;
    assign imem_h2d.we    = 1'b0;
    assign imem_h2d.addr  = pc_r;
    assign imem_h2d.wdata = 32'b0;
    assign imem_h2d.be    = 4'b1111;

    // ── Outputs ─────────────────────────────────────────────────────────
    assign pc_o    = pc_r;
    assign instr_o = imem_d2h.rdata;
    assign valid_o = imem_d2h.valid && !flush;

endmodule
