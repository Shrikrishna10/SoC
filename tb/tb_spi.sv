// ============================================================================
// tb_spi.sv — SPI testbench (loopback test)
// ============================================================================
// MOSI looped back to MISO. Sends a byte, verifies it comes back.
// ============================================================================

`include "tl_ul_defs.svh"

module tb_spi;

    logic clk, rst_n;
    tl_h2d_t tl_h2d;
    tl_d2h_t tl_d2h;
    logic spi_sclk, spi_mosi, spi_miso, spi_cs_n;
    logic irq;

    // Loopback: MOSI → MISO
    assign spi_miso = spi_mosi;

    spi_top #(.CLK_FREQ(50_000_000)) uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tl_h2d   (tl_h2d),
        .tl_d2h   (tl_d2h),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),
        .spi_cs_n (spi_cs_n),
        .irq      (irq)
    );

    initial clk = 0;
    always #10 clk = ~clk;

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

    task automatic tl_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        tl_h2d.valid <= 1'b1;
        tl_h2d.we    <= 1'b0;
        tl_h2d.addr  <= addr;
        tl_h2d.be    <= 4'hF;
        @(posedge clk);
        tl_h2d.valid <= 1'b0;
        @(posedge clk);
        data = tl_d2h.rdata;
    endtask

    localparam TXDATA = 32'h1002_0000;
    localparam RXDATA = 32'h1002_0004;
    localparam STATUS = 32'h1002_0008;
    localparam CTRL   = 32'h1002_000C;

    logic [31:0] read_val;

    initial begin
        rst_n = 0;
        tl_h2d = `TL_H2D_DEFAULT;
        #100;
        rst_n = 1;
        #100;

        $display("SPI TB: Configuring SPI (div=4, CPOL=0, CPHA=0)");
        // CTRL: div=4, CPOL=0, CPHA=0, IE=0
        tl_write(CTRL, 32'h0000_0004);

        #50;

        $display("SPI TB: Sending byte 0xA5...");
        tl_write(TXDATA, 32'h0000_00A5);

        // Wait for transfer to complete (8 bits * 2*(4+1) = 80 clocks + margin)
        repeat (500) @(posedge clk);

        // Check status
        tl_read(STATUS, read_val);
        $display("SPI TB: STATUS = %h (busy=%b, done=%b)", read_val, read_val[0], read_val[1]);

        // Read received data
        tl_read(RXDATA, read_val);
        $display("SPI TB: RXDATA = %h", read_val[7:0]);

        if (read_val[7:0] == 8'hA5)
            $display("=== SPI LOOPBACK TEST PASSED ===");
        else
            $display("=== SPI LOOPBACK TEST FAILED: expected 0xA5, got 0x%02h ===", read_val[7:0]);

        $finish;
    end

    initial begin
        #5_000_000;
        $display("SPI TB: TIMEOUT");
        $finish;
    end

endmodule
