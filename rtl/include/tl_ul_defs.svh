// ============================================================================
// tl_ul_defs.svh — TileLink-UL (Uncached Lightweight) bus definitions
// ============================================================================
// Minimal valid/ready handshake. A transfer occurs when BOTH valid and
// ready are high on a clock edge.
// ============================================================================

`ifndef TL_UL_DEFS_SVH
`define TL_UL_DEFS_SVH

// Host-to-Device request
typedef struct packed {
    logic        valid;
    logic        we;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [3:0]  be;
} tl_h2d_t;

// Device-to-Host response
typedef struct packed {
    logic        valid;
    logic        ready;
    logic [31:0] rdata;
    logic        error;
} tl_d2h_t;

`define TL_H2D_DEFAULT '{valid: 1'b0, we: 1'b0, addr: 32'h0, wdata: 32'h0, be: 4'h0}
`define TL_D2H_DEFAULT '{valid: 1'b0, ready: 1'b1, rdata: 32'h0, error: 1'b0}

`endif // TL_UL_DEFS_SVH
