// ============================================================================
// uart_top.sv — UART peripheral with TL-UL register interface
// ============================================================================
// Registers (word-aligned, byte offset from base):
//   0x00 TXDATA  [7:0] TX data (write: push to TX FIFO)
//   0x04 RXDATA  [7:0] RX data (read: pop from RX FIFO)
//   0x08 STATUS  [0] tx_full, [1] tx_empty, [2] rx_full, [3] rx_empty
//   0x0C CTRL    [15:0] baud divisor, [16] tx_ie, [17] rx_ie
//   0x10 IP      [0] tx_irq (tx FIFO below watermark), [1] rx_irq (rx FIFO has data)
// ============================================================================

`include "tl_ul_defs.svh"

module uart_top #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115200
)(
    input  logic        clk,
    input  logic        rst_n,

    // ── TL-UL device port ───────────────────────────────────────────────
    input  tl_h2d_t     tl_h2d,
    output tl_d2h_t     tl_d2h,

    // ── Physical I/O ────────────────────────────────────────────────────
    output logic        uart_tx,
    input  logic        uart_rx,

    // ── Interrupt ───────────────────────────────────────────────────────
    output logic        irq
);

    // ── Registers ───────────────────────────────────────────────────────
    logic [15:0] baud_div;
    logic        tx_ie, rx_ie;

    // ── Baud generator ──────────────────────────────────────────────────
    logic baud_tick;

    uart_baud_gen #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_baud (
        .clk     (clk),
        .rst_n   (rst_n),
        .div_val (baud_div),
        .tick    (baud_tick)
    );

    // ── TX FIFO ─────────────────────────────────────────────────────────
    logic        tx_fifo_wr, tx_fifo_rd;
    logic [7:0]  tx_fifo_wdata, tx_fifo_rdata;
    logic        tx_fifo_full, tx_fifo_empty;

    uart_fifo #(.WIDTH(8), .DEPTH(16)) u_tx_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (tx_fifo_wr),
        .wr_data (tx_fifo_wdata),
        .rd_en   (tx_fifo_rd),
        .rd_data (tx_fifo_rdata),
        .full    (tx_fifo_full),
        .empty   (tx_fifo_empty),
        .count   ()
    );

    // ── TX engine ───────────────────────────────────────────────────────
    logic tx_busy;

    uart_tx u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tick     (baud_tick),
        .tx_start (tx_fifo_rd),
        .tx_data  (tx_fifo_rdata),
        .tx_out   (uart_tx),
        .tx_busy  (tx_busy)
    );

    // Pop TX FIFO when transmitter is idle and FIFO has data
    assign tx_fifo_rd = !tx_busy && !tx_fifo_empty;

    // ── RX FIFO ─────────────────────────────────────────────────────────
    logic        rx_fifo_wr, rx_fifo_rd;
    logic [7:0]  rx_fifo_rdata;
    logic        rx_fifo_full, rx_fifo_empty;
    logic [7:0]  rx_byte;
    logic        rx_byte_valid;

    uart_rx u_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tick     (baud_tick),
        .rx_in    (uart_rx),
        .rx_data  (rx_byte),
        .rx_valid (rx_byte_valid)
    );

    assign rx_fifo_wr = rx_byte_valid && !rx_fifo_full;

    uart_fifo #(.WIDTH(8), .DEPTH(16)) u_rx_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (rx_fifo_wr),
        .wr_data (rx_byte),
        .rd_en   (rx_fifo_rd),
        .rd_data (rx_fifo_rdata),
        .full    (rx_fifo_full),
        .empty   (rx_fifo_empty),
        .count   ()
    );

    // ── Interrupts ──────────────────────────────────────────────────────
    logic tx_irq, rx_irq;
    assign tx_irq = tx_ie && tx_fifo_empty;
    assign rx_irq = rx_ie && !rx_fifo_empty;
    assign irq = tx_irq || rx_irq;

    // ── TL-UL register interface ────────────────────────────────────────
    logic [7:0] reg_offset;
    assign reg_offset = tl_h2d.addr[7:0];

    // Read
    logic [31:0] rdata;
    logic rsp_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata     <= 32'b0;
            rsp_valid <= 1'b0;
        end else begin
            rsp_valid <= tl_h2d.valid && !tl_h2d.we;
            if (tl_h2d.valid && !tl_h2d.we) begin
                case (reg_offset)
                    8'h00: rdata <= {24'b0, tx_fifo_rdata};  // TXDATA (read drain — typically not used)
                    8'h04: rdata <= {24'b0, rx_fifo_rdata};  // RXDATA
                    8'h08: rdata <= {28'b0, rx_fifo_empty, rx_fifo_full,
                                     tx_fifo_empty, tx_fifo_full};  // STATUS
                    8'h0C: rdata <= {14'b0, rx_ie, tx_ie, baud_div};  // CTRL
                    8'h10: rdata <= {30'b0, rx_irq, tx_irq};  // IP
                    default: rdata <= 32'b0;
                endcase
            end
        end
    end

    // Pop RX FIFO on RXDATA read
    assign rx_fifo_rd = tl_h2d.valid && !tl_h2d.we && (reg_offset == 8'h04);

    // Write
    assign tx_fifo_wr    = tl_h2d.valid && tl_h2d.we && (reg_offset == 8'h00) && !tx_fifo_full;
    assign tx_fifo_wdata = tl_h2d.wdata[7:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_div <= 16'b0;
            tx_ie    <= 1'b0;
            rx_ie    <= 1'b0;
        end else if (tl_h2d.valid && tl_h2d.we) begin
            case (reg_offset)
                8'h0C: begin
                    baud_div <= tl_h2d.wdata[15:0];
                    tx_ie    <= tl_h2d.wdata[16];
                    rx_ie    <= tl_h2d.wdata[17];
                end
                default: ;
            endcase
        end
    end

    // TL-UL response
    assign tl_d2h.ready = 1'b1;
    assign tl_d2h.valid = rsp_valid;
    assign tl_d2h.rdata = rdata;
    assign tl_d2h.error = 1'b0;

endmodule
