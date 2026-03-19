// ============================================================================
// spi_clkgen.sv — SPI clock generator
// ============================================================================
// Divides system clock by a configurable divisor to produce SCLK.
// Supports CPOL (clock polarity) configuration.
// ============================================================================

module spi_clkgen (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic [7:0]  div_val,    // clock divisor (SCLK = clk / (2*(div+1)))
    input  logic        cpol,       // clock polarity

    output logic        sclk,       // SPI clock output
    output logic        sclk_edge,  // pulses on SCLK edges (for shifting)
    output logic        sample_edge // pulses when data should be sampled
);

    logic [7:0] counter;
    logic       sclk_int;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter  <= 8'b0;
            sclk_int <= 1'b0;
        end else if (enable) begin
            if (counter >= div_val) begin
                counter  <= 8'b0;
                sclk_int <= ~sclk_int;
            end else begin
                counter <= counter + 8'd1;
            end
        end else begin
            counter  <= 8'b0;
            sclk_int <= 1'b0;
        end
    end

    assign sclk = sclk_int ^ cpol;

    // Edge detection for shift/sample
    logic sclk_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sclk_prev <= 1'b0;
        else
            sclk_prev <= sclk_int;
    end

    // For CPHA=0: sample on rising, shift on falling
    // For CPHA=1: sample on falling, shift on rising
    // We expose both edges; spi_master selects based on CPHA
    assign sclk_edge   = sclk_int && !sclk_prev;   // rising edge of internal clock
    assign sample_edge = !sclk_int && sclk_prev;    // falling edge of internal clock

endmodule
