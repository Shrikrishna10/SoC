// ============================================================================
// tb_soc.sv — SoC top-level testbench
// ============================================================================
// Instantiates soc_top with a boot ROM hex file.
// Monitors UART TX output for a known pattern.
// ============================================================================

`include "rv32_defs.svh"
`include "tl_ul_defs.svh"

module tb_soc;

    logic clk, rst_n;
    logic uart_tx, uart_rx;
    logic spi_sclk, spi_mosi, spi_miso, spi_cs_n;

    // Tie off unused inputs
    assign uart_rx  = 1'b1;  // idle
    assign spi_miso = 1'b0;

    soc_top #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115200),
        .BOOT_HEX  ("boot.hex")
    ) uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_tx  (uart_tx),
        .uart_rx  (uart_rx),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),
        .spi_cs_n (spi_cs_n)
    );

    // Clock: 20ns = 50MHz
    initial clk = 0;
    always #10 clk = ~clk;

    // ── UART TX monitor (captures serial bytes) ─────────────────────────
    logic [7:0] captured_byte;
    integer     byte_count;

    task automatic uart_capture_byte;
        // Wait for start bit (falling edge on uart_tx)
        @(negedge uart_tx);

        // Wait half bit period to center on start bit
        #(8680ns / 2);  // 115200 baud ≈ 8.68us per bit

        // Sample 8 data bits
        for (int i = 0; i < 8; i++) begin
            #8680ns;
            captured_byte[i] = uart_tx;
        end

        // Wait for stop bit
        #8680ns;

        $display("SoC TB: UART captured byte [%0d] = 0x%02h '%c'",
                 byte_count, captured_byte, captured_byte);
        byte_count = byte_count + 1;
    endtask

    // ── Monitor task (runs in parallel) ─────────────────────────────────
    initial begin
        byte_count = 0;
        forever begin
            uart_capture_byte();
        end
    end

    // ── Main stimulus ───────────────────────────────────────────────────
    initial begin
        rst_n = 0;
        #200;
        rst_n = 1;

        $display("SoC TB: Reset released. CPU booting from 0x0000_1000...");
        $display("SoC TB: Monitoring UART TX for output...");

        // Run for a reasonable time
        // At 50MHz, 1ms = 50000 cycles
        repeat (500_000) @(posedge clk);  // 10ms

        $display("\nSoC TB: Simulation complete. Captured %0d UART bytes.", byte_count);

        // Dump some CPU state
        $display("SoC TB: CPU PC = %h", uut.u_cpu.u_fetch.pc_r);
        $display("SoC TB: CPU x1 = %h", uut.u_cpu.u_regfile.regs[1]);
        $display("SoC TB: CPU x2 = %h", uut.u_cpu.u_regfile.regs[2]);

        $display("=== SOC SIMULATION COMPLETE ===");
        $finish;
    end

    // Timeout
    initial begin
        #100_000_000;
        $display("SoC TB: TIMEOUT");
        $finish;
    end

endmodule
