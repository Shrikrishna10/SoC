// ============================================================================
// spi_top.sv — SPI peripheral with TL-UL register interface
// ============================================================================
// Registers (word-aligned, byte offset from base):
//   0x00 TXDATA  [7:0]  TX data (write: start transfer)
//   0x04 RXDATA  [7:0]  RX data (read: last received byte)
//   0x08 STATUS  [0] busy, [1] done (write-1-to-clear)
//   0x0C CTRL    [7:0] clock divisor, [8] CPOL, [9] CPHA, [10] IE
// ============================================================================

`include "tl_ul_defs.svh"

module spi_top #(
    parameter int CLK_FREQ = 50_000_000
)(
    input  logic        clk,
    input  logic        rst_n,

    // ── TL-UL device port ───────────────────────────────────────────────
    input  tl_h2d_t     tl_h2d,
    output tl_d2h_t     tl_d2h,

    // ── SPI signals ─────────────────────────────────────────────────────
    output logic        spi_sclk,
    output logic        spi_mosi,
    input  logic        spi_miso,
    output logic        spi_cs_n,

    // ── Interrupt ───────────────────────────────────────────────────────
    output logic        irq
);

    // ── Control registers ───────────────────────────────────────────────
    logic [7:0] clk_div;
    logic       cpol, cpha, ie;
    logic       cs_n_reg;

    // ── SPI clock generator ─────────────────────────────────────────────
    logic sclk_edge, sample_edge;
    logic spi_active;

    spi_clkgen u_clkgen (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (spi_active),
        .div_val     (clk_div),
        .cpol        (cpol),
        .sclk        (spi_sclk),
        .sclk_edge   (sclk_edge),
        .sample_edge (sample_edge)
    );

    // ── SPI master ──────────────────────────────────────────────────────
    logic       spi_start, spi_busy, spi_done;
    logic [7:0] spi_tx_data, spi_rx_data;

    spi_master u_master (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (spi_start),
        .tx_data     (spi_tx_data),
        .cpha        (cpha),
        .sclk_edge   (sclk_edge),
        .sample_edge (sample_edge),
        .mosi        (spi_mosi),
        .miso        (spi_miso),
        .rx_data     (spi_rx_data),
        .busy        (spi_busy),
        .done        (spi_done)
    );

    assign spi_active = spi_busy;
    assign spi_cs_n   = cs_n_reg;

    // Status register
    logic done_flag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            done_flag <= 1'b0;
        else if (spi_done)
            done_flag <= 1'b1;
        else if (tl_h2d.valid && tl_h2d.we && (tl_h2d.addr[7:0] == 8'h08))
            done_flag <= done_flag & ~tl_h2d.wdata[1];  // write-1-to-clear
    end

    assign irq = ie && done_flag;

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
                    8'h00: rdata <= 32'b0;  // TXDATA (write-only)
                    8'h04: rdata <= {24'b0, spi_rx_data};
                    8'h08: rdata <= {30'b0, done_flag, spi_busy};
                    8'h0C: rdata <= {21'b0, ie, cpha, cpol, clk_div};
                    default: rdata <= 32'b0;
                endcase
            end
        end
    end

    // Write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div   <= 8'd0;
            cpol      <= 1'b0;
            cpha      <= 1'b0;
            ie        <= 1'b0;
            cs_n_reg  <= 1'b1;  // deasserted by default
            spi_start <= 1'b0;
            spi_tx_data <= 8'b0;
        end else begin
            spi_start <= 1'b0;

            if (tl_h2d.valid && tl_h2d.we) begin
                case (reg_offset)
                    8'h00: begin  // TXDATA — start transfer
                        if (!spi_busy) begin
                            spi_tx_data <= tl_h2d.wdata[7:0];
                            spi_start   <= 1'b1;
                            cs_n_reg    <= 1'b0;  // assert CS
                        end
                    end
                    8'h0C: begin  // CTRL
                        clk_div <= tl_h2d.wdata[7:0];
                        cpol    <= tl_h2d.wdata[8];
                        cpha    <= tl_h2d.wdata[9];
                        ie      <= tl_h2d.wdata[10];
                    end
                    default: ;
                endcase
            end

            // Deassert CS after transfer completes
            if (spi_done)
                cs_n_reg <= 1'b1;
        end
    end

    // TL-UL response
    assign tl_d2h.ready = 1'b1;
    assign tl_d2h.valid = rsp_valid;
    assign tl_d2h.rdata = rdata;
    assign tl_d2h.error = 1'b0;

endmodule
