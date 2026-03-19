// ============================================================================
// spi_master.sv — SPI Master shift engine
// ============================================================================
// 8-bit, MSB-first shift register.
// Configurable CPOL/CPHA via edge selection.
// ============================================================================

module spi_master (
    input  logic       clk,
    input  logic       rst_n,

    // ── Control ─────────────────────────────────────────────────────────
    input  logic       start,       // pulse to begin transfer
    input  logic [7:0] tx_data,     // data to transmit
    input  logic       cpha,        // clock phase

    // ── Clock edges from spi_clkgen ─────────────────────────────────────
    input  logic       sclk_edge,   // rising of internal clock
    input  logic       sample_edge, // falling of internal clock

    // ── SPI signals ─────────────────────────────────────────────────────
    output logic       mosi,
    input  logic       miso,

    // ── Status / output ─────────────────────────────────────────────────
    output logic [7:0] rx_data,
    output logic       busy,
    output logic       done         // pulse when transfer complete
);

    logic [7:0] shift_tx;
    logic [7:0] shift_rx;
    logic [2:0] bit_cnt;
    logic       active;

    // Shift and sample edge selection based on CPHA
    logic do_shift, do_sample;
    assign do_shift  = cpha ? sample_edge : sclk_edge;
    assign do_sample = cpha ? sclk_edge   : sample_edge;

    assign busy = active;
    assign mosi = shift_tx[7];  // MSB first

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_tx <= 8'b0;
            shift_rx <= 8'b0;
            bit_cnt  <= 3'b0;
            active   <= 1'b0;
            done     <= 1'b0;
            rx_data  <= 8'b0;
        end else begin
            done <= 1'b0;

            if (start && !active) begin
                shift_tx <= tx_data;
                shift_rx <= 8'b0;
                bit_cnt  <= 3'b0;
                active   <= 1'b1;
            end else if (active) begin
                if (do_sample) begin
                    shift_rx <= {shift_rx[6:0], miso};
                end

                if (do_shift) begin
                    shift_tx <= {shift_tx[6:0], 1'b0};
                    if (bit_cnt == 3'd7) begin
                        active  <= 1'b0;
                        done    <= 1'b1;
                        rx_data <= {shift_rx[6:0], miso};  // capture last bit
                    end else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end
            end
        end
    end

endmodule
