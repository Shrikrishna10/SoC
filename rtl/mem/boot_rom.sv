// ============================================================================
// boot_rom.sv — 256-word boot ROM with TL-UL interface
// ============================================================================
// Read-only memory mapped at 0x0000_1000. Loaded via $readmemh.
// Single-cycle read, TL-UL compatible.
// ============================================================================

`include "tl_ul_defs.svh"

module boot_rom #(
    parameter int WORDS    = 256,
    parameter     MEM_FILE = "boot.hex"
)(
    input  logic        clk,
    input  logic        rst_n,

    // ── TL-UL device port ───────────────────────────────────────────────
    input  tl_h2d_t     tl_h2d,
    output tl_d2h_t     tl_d2h
);

    localparam int AW = $clog2(WORDS);

    logic [31:0] rom [0:WORDS-1];

    initial begin
        $readmemh(MEM_FILE, rom);
    end

    // Word address from byte address
    logic [AW-1:0] word_addr;
    assign word_addr = tl_h2d.addr[AW+1:2];

    // Read data (synchronous for BRAM inference)
    logic [31:0] rdata_r;
    logic        valid_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_r <= 32'b0;
            valid_r <= 1'b0;
        end else begin
            rdata_r <= rom[word_addr];
            valid_r <= tl_h2d.valid && !tl_h2d.we;
        end
    end

    // TL-UL response
    assign tl_d2h.ready = 1'b1;
    assign tl_d2h.valid = valid_r;
    assign tl_d2h.rdata = rdata_r;
    assign tl_d2h.error = tl_h2d.valid && tl_h2d.we;  // error on write attempt

endmodule
