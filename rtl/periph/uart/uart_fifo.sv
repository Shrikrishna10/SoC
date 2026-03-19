// ============================================================================
// uart_fifo.sv — Simple synchronous FIFO
// ============================================================================
// Parameterized depth (power of 2). Used for TX and RX FIFOs.
// ============================================================================

module uart_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16   // must be power of 2
)(
    input  logic             clk,
    input  logic             rst_n,

    // Write port
    input  logic             wr_en,
    input  logic [WIDTH-1:0] wr_data,

    // Read port
    input  logic             rd_en,
    output logic [WIDTH-1:0] rd_data,

    // Status
    output logic             full,
    output logic             empty,
    output logic [$clog2(DEPTH):0] count
);

    localparam int AW = $clog2(DEPTH);

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [AW:0] wr_ptr, rd_ptr;  // extra bit for full/empty detection

    assign count = wr_ptr - rd_ptr;
    assign full  = (count == DEPTH[AW:0]);
    assign empty = (wr_ptr == rd_ptr);

    assign rd_data = mem[rd_ptr[AW-1:0]];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[AW-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end

endmodule
