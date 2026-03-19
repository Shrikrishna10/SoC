// ============================================================================
// uart_baud_gen.sv — Baud rate generator
// ============================================================================
// Divides system clock to produce a tick at the desired baud rate.
// tick output pulses once per bit period.
// ============================================================================

module uart_baud_gen #(
    parameter int CLK_FREQ  = 50_000_000,  // default 50 MHz
    parameter int BAUD_RATE = 115200
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] div_val,    // runtime-configurable divisor (0 = use default)
    output logic        tick        // pulses at baud rate
);

    localparam int DEFAULT_DIV = CLK_FREQ / BAUD_RATE - 1;

    logic [15:0] divisor;
    assign divisor = (div_val != 16'b0) ? div_val : DEFAULT_DIV[15:0];

    logic [15:0] counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 16'b0;
            tick    <= 1'b0;
        end else begin
            if (counter >= divisor) begin
                counter <= 16'b0;
                tick    <= 1'b1;
            end else begin
                counter <= counter + 16'd1;
                tick    <= 1'b0;
            end
        end
    end

endmodule
