// ============================================================================
// uart_tx.sv — UART Transmitter
// ============================================================================
// 8N1: 1 start bit, 8 data bits, no parity, 1 stop bit.
// Shifts out LSB first on each baud tick.
// ============================================================================

module uart_tx (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tick,       // baud rate tick
    input  logic       tx_start,   // pulse to begin transmission
    input  logic [7:0] tx_data,    // byte to send
    output logic       tx_out,     // serial output
    output logic       tx_busy     // 1 while transmitting
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

    assign tx_busy = (state != IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx_out    <= 1'b1;   // idle high
            shift_reg <= 8'b0;
            bit_cnt   <= 3'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        state     <= START;
                    end
                end

                START: begin
                    if (tick) begin
                        tx_out  <= 1'b0;  // start bit
                        state   <= DATA;
                        bit_cnt <= 3'b0;
                    end
                end

                DATA: begin
                    if (tick) begin
                        tx_out    <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};  // shift right
                        if (bit_cnt == 3'd7)
                            state <= STOP;
                        else
                            bit_cnt <= bit_cnt + 3'd1;
                    end
                end

                STOP: begin
                    if (tick) begin
                        tx_out <= 1'b1;  // stop bit
                        state  <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
