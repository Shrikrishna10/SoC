// ============================================================================
// tb_uart.sv — UART testbench (loopback test)
// ============================================================================
// Writes a byte to the TX FIFO via TL-UL, captures the serial output,
// feeds it back to RX, and reads it from the RX FIFO via TL-UL.
// ============================================================================

`include "tl_ul_defs.svh"

module tb_uart;

    logic clk, rst_n;
    tl_h2d_t tl_h2d;
    tl_d2h_t tl_d2h;
    logic uart_tx_pin, uart_rx_pin;
    logic irq;

    // Loopback: TX → RX
    assign uart_rx_pin = uart_tx_pin;

    uart_top #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115200)
    ) uut (
        .clk     (clk),
        .rst_n   (rst_n),
        .tl_h2d  (tl_h2d),
        .tl_d2h  (tl_d2h),
        .uart_tx (uart_tx_pin),
        .uart_rx (uart_rx_pin),
        .irq     (irq)
    );

    // Clock: 20ns = 50MHz
    initial clk = 0;
    always #10 clk = ~clk;

    // TL-UL write helper
    task automatic tl_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk);
        tl_h2d.valid <= 1'b1;
        tl_h2d.we    <= 1'b1;
        tl_h2d.addr  <= addr;
        tl_h2d.wdata <= data;
        tl_h2d.be    <= 4'hF;
        @(posedge clk);
        tl_h2d.valid <= 1'b0;
        tl_h2d.we    <= 1'b0;
    endtask

    // TL-UL read helper
    task automatic tl_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        tl_h2d.valid <= 1'b1;
        tl_h2d.we    <= 1'b0;
        tl_h2d.addr  <= addr;
        tl_h2d.wdata <= 32'b0;
        tl_h2d.be    <= 4'hF;
        @(posedge clk);
        tl_h2d.valid <= 1'b0;
        @(posedge clk); // wait for response
        data = tl_d2h.rdata;
    endtask

    localparam TXDATA = 32'h1001_0000;
    localparam RXDATA = 32'h1001_0004;
    localparam STATUS = 32'h1001_0008;

    logic [31:0] read_val;
    integer i;

    initial begin
        rst_n = 0;
        tl_h2d = `TL_H2D_DEFAULT;
        #100;
        rst_n = 1;
        #100;

        $display("UART TB: Sending byte 0x55 via TX...");

        // Write 0x55 to TXDATA
        tl_write(TXDATA, 32'h55);

        // Wait for transmission + reception (8N1 at 115200 baud ≈ 87us)
        // At 50MHz, 87us ≈ 4350 clocks. Wait extra for safety.
        for (i = 0; i < 10000; i++) @(posedge clk);

        // Check status: rx should have data (rx_empty = bit[3] = 0)
        tl_read(STATUS, read_val);
        $display("UART TB: STATUS = %h", read_val);

        // Read RXDATA
        tl_read(RXDATA, read_val);
        $display("UART TB: RXDATA = %h", read_val[7:0]);

        if (read_val[7:0] == 8'h55)
            $display("=== UART LOOPBACK TEST PASSED ===");
        else
            $display("=== UART LOOPBACK TEST FAILED: expected 0x55, got 0x%02h ===", read_val[7:0]);

        $finish;
    end

    // Timeout
    initial begin
        #50_000_000;
        $display("UART TB: TIMEOUT");
        $finish;
    end

endmodule
