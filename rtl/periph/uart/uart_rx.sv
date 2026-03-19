// ============================================================================
// uart_rx.sv — UART Receiver
// ============================================================================
// 8N1: samples at mid-bit using 16x oversampled tick.
// Detects start bit falling edge, then samples 8 data bits LSB first.
// ============================================================================

module uart_rx (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tick,        // baud rate tick (1x)
    input  logic       rx_in,       // serial input
    output logic [7:0] rx_data,     // received byte
    output logic       rx_valid     // pulse when byte is complete
);

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    state_t state;
    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic [3:0] sample_cnt;   // for mid-bit sampling (count to ~half bit period)

    // Synchronize rx_in to avoid metastability
    logic rx_sync0, rx_sync1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx_in;
            rx_sync1 <= rx_sync0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            shift_reg  <= 8'b0;
            bit_cnt    <= 3'b0;
            sample_cnt <= 4'b0;
            rx_data    <= 8'b0;
            rx_valid   <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (!rx_sync1) begin  // falling edge = start bit
                        state      <= START;
                        sample_cnt <= 4'b0;
                    end
                end

                START: begin
                    if (tick) begin
                        // Wait half a bit period to sample at center of start bit
                        if (sample_cnt == 4'd7) begin
                            if (!rx_sync1) begin
                                // Valid start bit
                                state      <= DATA;
                                sample_cnt <= 4'b0;
                                bit_cnt    <= 3'b0;
                            end else begin
                                // False start, go back
                                state <= IDLE;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end
                end

                DATA: begin
                    if (tick) begin
                        if (sample_cnt == 4'd15) begin
                            // Sample at mid-bit
                            shift_reg <= {rx_sync1, shift_reg[7:1]};
                            sample_cnt <= 4'b0;
                            if (bit_cnt == 3'd7)
                                state <= STOP;
                            else
                                bit_cnt <= bit_cnt + 3'd1;
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end
                end

                STOP: begin
                    if (tick) begin
                        if (sample_cnt == 4'd15) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                            state    <= IDLE;
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
