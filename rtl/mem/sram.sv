// ============================================================================
// sram.sv — Parameterized byte-enable SRAM
// ============================================================================
// Synthesizable on Xilinx (infers BRAM).
// Single-port: 1 read/write per cycle.
// Byte-enable for sub-word writes.
// ============================================================================

module sram #(
    parameter int ADDR_WIDTH = 14,  // word address bits (2^14 = 16K words = 64KB)
    parameter int DATA_WIDTH = 32
)(
    input  logic                     clk,
    input  logic                     req,
    input  logic                     we,
    input  logic [ADDR_WIDTH-1:0]    addr,
    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [DATA_WIDTH/8-1:0]  be,
    output logic [DATA_WIDTH-1:0]    rdata
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    // Infers BRAM on Xilinx
    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (req) begin
            if (we) begin
                // Byte-enable write
                if (be[0]) mem[addr][7:0]   <= wdata[7:0];
                if (be[1]) mem[addr][15:8]  <= wdata[15:8];
                if (be[2]) mem[addr][23:16] <= wdata[23:16];
                if (be[3]) mem[addr][31:24] <= wdata[31:24];
            end
            rdata <= mem[addr];
        end
    end

endmodule
