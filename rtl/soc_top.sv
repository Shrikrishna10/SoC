// ============================================================================
// soc_top.sv — RV32IMC SoC top-level
// ============================================================================
// Instantiates CPU, TL-UL crossbar, SRAM, Boot ROM, UART, SPI, PLIC, CLINT.
//
// Memory Map:
//   0x0000_1000 – 0x0000_1FFF  Boot ROM     (4 KB)
//   0x0200_0000 – 0x0200_FFFF  CLINT        (64 KB)
//   0x0C00_0000 – 0x0C00_FFFF  PLIC         (64 KB)
//   0x1001_0000 – 0x1001_00FF  UART         (256 B)
//   0x1002_0000 – 0x1002_00FF  SPI          (256 B)
//   0x8000_0000 – 0x8000_FFFF  SRAM         (64 KB)
// ============================================================================

`include "rv32_defs.svh"
`include "tl_ul_defs.svh"

module soc_top #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115200,
    parameter     BOOT_HEX  = "boot.hex"
)(
    input  logic        clk,
    input  logic        rst_n,

    // ── External I/O ────────────────────────────────────────────────────
    output logic        uart_tx,
    input  logic        uart_rx,

    output logic        spi_sclk,
    output logic        spi_mosi,
    input  logic        spi_miso,
    output logic        spi_cs_n
);

    // ====================================================================
    // Internal TL-UL buses
    // ====================================================================
    localparam int N_DEV = 6;

    tl_h2d_t ibus_h2d, dbus_h2d;
    tl_d2h_t ibus_d2h, dbus_d2h;

    tl_h2d_t dev_h2d [N_DEV];
    tl_d2h_t dev_d2h [N_DEV];

    // ====================================================================
    // Interrupt wiring
    // ====================================================================
    logic ext_irq, timer_irq, sw_irq;
    logic uart_irq, spi_irq;

    // PLIC sources: [0] reserved, [1] UART, [2] SPI, [3..7] unused
    logic [7:0] plic_sources;
    assign plic_sources = {5'b0, spi_irq, uart_irq, 1'b0};

    // ====================================================================
    // CPU
    // ====================================================================
    cpu_top u_cpu (
        .clk       (clk),
        .rst_n     (rst_n),
        .imem_h2d  (ibus_h2d),
        .imem_d2h  (ibus_d2h),
        .dmem_h2d  (dbus_h2d),
        .dmem_d2h  (dbus_d2h),
        .ext_irq   (ext_irq),
        .timer_irq (timer_irq),
        .sw_irq    (sw_irq)
    );

    // ====================================================================
    // Crossbar
    // ====================================================================
    tl_xbar #(.N_DEVICES(N_DEV)) u_xbar (
        .clk      (clk),
        .rst_n    (rst_n),
        .ibus_h2d (ibus_h2d),
        .ibus_d2h (ibus_d2h),
        .dbus_h2d (dbus_h2d),
        .dbus_d2h (dbus_d2h),
        .dev_h2d  (dev_h2d),
        .dev_d2h  (dev_d2h)
    );

    // ====================================================================
    // Device 0: Boot ROM (0x0000_1000)
    // ====================================================================
    boot_rom #(
        .WORDS    (256),
        .MEM_FILE (BOOT_HEX)
    ) u_boot_rom (
        .clk    (clk),
        .rst_n  (rst_n),
        .tl_h2d (dev_h2d[0]),
        .tl_d2h (dev_d2h[0])
    );

    // ====================================================================
    // Device 1: CLINT (0x0200_0000)
    // ====================================================================
    clint u_clint (
        .clk       (clk),
        .rst_n     (rst_n),
        .tl_h2d    (dev_h2d[1]),
        .tl_d2h    (dev_d2h[1]),
        .timer_irq (timer_irq),
        .sw_irq    (sw_irq)
    );

    // ====================================================================
    // Device 2: PLIC (0x0C00_0000)
    // ====================================================================
    plic #(.N_SRC(8)) u_plic (
        .clk         (clk),
        .rst_n       (rst_n),
        .tl_h2d      (dev_h2d[2]),
        .tl_d2h      (dev_d2h[2]),
        .irq_sources (plic_sources),
        .ext_irq     (ext_irq)
    );

    // ====================================================================
    // Device 3: UART (0x1001_0000)
    // ====================================================================
    uart_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .tl_h2d  (dev_h2d[3]),
        .tl_d2h  (dev_d2h[3]),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx),
        .irq     (uart_irq)
    );

    // ====================================================================
    // Device 4: SPI (0x1002_0000)
    // ====================================================================
    spi_top #(
        .CLK_FREQ(CLK_FREQ)
    ) u_spi (
        .clk      (clk),
        .rst_n    (rst_n),
        .tl_h2d   (dev_h2d[4]),
        .tl_d2h   (dev_d2h[4]),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),
        .spi_cs_n (spi_cs_n),
        .irq      (spi_irq)
    );

    // ====================================================================
    // Device 5: SRAM (0x8000_0000, 64 KB)
    // ====================================================================
    // TL-UL adapter → SRAM
    logic        sram_req, sram_we;
    logic [13:0] sram_addr;
    logic [31:0] sram_wdata, sram_rdata;
    logic [3:0]  sram_be;

    tl_adapter_sram #(.ADDR_WIDTH(14)) u_sram_adapter (
        .clk       (clk),
        .rst_n     (rst_n),
        .tl_h2d    (dev_h2d[5]),
        .tl_d2h    (dev_d2h[5]),
        .sram_req  (sram_req),
        .sram_we   (sram_we),
        .sram_addr (sram_addr),
        .sram_wdata(sram_wdata),
        .sram_be   (sram_be),
        .sram_rdata(sram_rdata)
    );

    sram #(.ADDR_WIDTH(14)) u_sram (
        .clk   (clk),
        .req   (sram_req),
        .we    (sram_we),
        .addr  (sram_addr),
        .wdata (sram_wdata),
        .be    (sram_be),
        .rdata (sram_rdata)
    );

endmodule
