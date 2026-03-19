// ============================================================================
// tl_adapter_sram.sv — TL-UL ↔ SRAM bridge
// ============================================================================
// Converts TL-UL valid/ready handshake to simple SRAM signals.
// Single-cycle response: always ready, read data valid next cycle.
// ============================================================================

`include "tl_ul_defs.svh"

module tl_adapter_sram #(
    parameter int ADDR_WIDTH = 14   // byte address width (64KB = 16 bits, word = 14)
)(
    input  logic        clk,
    input  logic        rst_n,

    // ── TL-UL device port ───────────────────────────────────────────────
    input  tl_h2d_t     tl_h2d,
    output tl_d2h_t     tl_d2h,

    // ── SRAM interface ──────────────────────────────────────────────────
    output logic                     sram_req,
    output logic                     sram_we,
    output logic [ADDR_WIDTH-1:0]    sram_addr,   // word address
    output logic [31:0]              sram_wdata,
    output logic [3:0]               sram_be,
    input  logic [31:0]              sram_rdata
);

    // ── Request generation ──────────────────────────────────────────────
    assign sram_req   = tl_h2d.valid;
    assign sram_we    = tl_h2d.we;
    assign sram_addr  = tl_h2d.addr[ADDR_WIDTH+1:2];  // convert byte addr → word addr
    assign sram_wdata = tl_h2d.wdata;
    assign sram_be    = tl_h2d.be;

    // ── Response: always ready, data valid one cycle after request ───────
    logic rsp_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rsp_valid <= 1'b0;
        else
            rsp_valid <= tl_h2d.valid && !tl_h2d.we;  // read requests
    end

    assign tl_d2h.ready = 1'b1;         // SRAM is always ready
    assign tl_d2h.valid = rsp_valid;
    assign tl_d2h.rdata = sram_rdata;
    assign tl_d2h.error = 1'b0;

endmodule
