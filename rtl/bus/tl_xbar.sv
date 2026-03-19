// ============================================================================
// tl_xbar.sv — TileLink-UL crossbar (1x2 host, N devices)
// ============================================================================
// Two host ports: I-bus (instruction) and D-bus (data).
// Round-robin arbiter when both contend for the same device.
// Address decoder routes to devices based on upper address bits.
// Returns error for unmapped addresses.
// ============================================================================

`include "tl_ul_defs.svh"

module tl_xbar #(
    parameter int N_DEVICES = 6   // number of device ports
)(
    input  logic        clk,
    input  logic        rst_n,

    // ── Host ports (from CPU) ───────────────────────────────────────────
    input  tl_h2d_t     ibus_h2d,     // instruction bus
    output tl_d2h_t     ibus_d2h,
    input  tl_h2d_t     dbus_h2d,     // data bus
    output tl_d2h_t     dbus_d2h,

    // ── Device ports ────────────────────────────────────────────────────
    output tl_h2d_t     dev_h2d [N_DEVICES],
    input  tl_d2h_t     dev_d2h [N_DEVICES]
);

    // ── Address decoder ─────────────────────────────────────────────────
    // Returns device index for a given address, or -1 for unmapped.
    // Memory map (from implementation plan):
    //   0 : 0x0000_1000 – 0x0000_1FFF  Boot ROM
    //   1 : 0x0200_0000 – 0x0200_FFFF  CLINT
    //   2 : 0x0C00_0000 – 0x0C00_FFFF  PLIC
    //   3 : 0x1001_0000 – 0x1001_00FF  UART
    //   4 : 0x1002_0000 – 0x1002_00FF  SPI
    //   5 : 0x8000_0000 – 0x8000_FFFF  SRAM

    function automatic int addr_to_dev(input logic [31:0] addr);
        if (addr[31:12] == 20'h00001)                      return 0;  // Boot ROM
        else if (addr[31:16] == 16'h0200)                  return 1;  // CLINT
        else if (addr[31:16] == 16'h0C00)                  return 2;  // PLIC
        else if (addr[31:8]  == 24'h100100)                return 3;  // UART
        else if (addr[31:8]  == 24'h100200)                return 4;  // SPI
        else if (addr[31:16] == 16'h8000)                  return 5;  // SRAM
        else                                               return -1; // unmapped
    endfunction

    // ── Arbitration state ───────────────────────────────────────────────
    logic last_grant;  // 0 = ibus, 1 = dbus (for round-robin)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            last_grant <= 1'b0;
        else if (ibus_h2d.valid && dbus_h2d.valid)
            last_grant <= ~last_grant;
    end

    // ── Route requests ──────────────────────────────────────────────────
    int ibus_dev, dbus_dev;
    assign ibus_dev = addr_to_dev(ibus_h2d.addr);
    assign dbus_dev = addr_to_dev(dbus_h2d.addr);

    // Contention: both buses want the same device at the same time
    logic contention;
    assign contention = ibus_h2d.valid && dbus_h2d.valid &&
                        (ibus_dev == dbus_dev) && (ibus_dev >= 0);

    // Grant signals
    logic ibus_grant, dbus_grant;

    always_comb begin
        if (contention) begin
            // Round-robin: alternate priority
            ibus_grant = ~last_grant;
            dbus_grant =  last_grant;
        end else begin
            ibus_grant = ibus_h2d.valid;
            dbus_grant = dbus_h2d.valid;
        end
    end

    // ── Drive device ports ──────────────────────────────────────────────
    integer i;
    always_comb begin
        // Default: all devices idle
        for (i = 0; i < N_DEVICES; i = i + 1) begin
            dev_h2d[i].valid = 1'b0;
            dev_h2d[i].we    = 1'b0;
            dev_h2d[i].addr  = 32'b0;
            dev_h2d[i].wdata = 32'b0;
            dev_h2d[i].be    = 4'b0;
        end

        // Route ibus
        if (ibus_grant && ibus_dev >= 0) begin
            dev_h2d[ibus_dev].valid = 1'b1;
            dev_h2d[ibus_dev].we    = ibus_h2d.we;
            dev_h2d[ibus_dev].addr  = ibus_h2d.addr;
            dev_h2d[ibus_dev].wdata = ibus_h2d.wdata;
            dev_h2d[ibus_dev].be    = ibus_h2d.be;
        end

        // Route dbus (won't conflict because of arbitration)
        if (dbus_grant && dbus_dev >= 0) begin
            if (!(contention && !dbus_grant)) begin  // not stalled by contention
                dev_h2d[dbus_dev].valid = 1'b1;
                dev_h2d[dbus_dev].we    = dbus_h2d.we;
                dev_h2d[dbus_dev].addr  = dbus_h2d.addr;
                dev_h2d[dbus_dev].wdata = dbus_h2d.wdata;
                dev_h2d[dbus_dev].be    = dbus_h2d.be;
            end
        end
    end

    // ── Drive host responses ────────────────────────────────────────────
    // Error response for unmapped addresses
    tl_d2h_t error_resp;
    assign error_resp.valid = 1'b1;
    assign error_resp.ready = 1'b1;
    assign error_resp.rdata = 32'hDEAD_BEEF;
    assign error_resp.error = 1'b1;

    always_comb begin
        // I-bus response
        if (!ibus_h2d.valid) begin
            ibus_d2h = `TL_D2H_DEFAULT;
        end else if (ibus_dev < 0) begin
            ibus_d2h = error_resp;
        end else if (contention && !ibus_grant) begin
            // Stalled — device not ready
            ibus_d2h.valid = 1'b0;
            ibus_d2h.ready = 1'b0;
            ibus_d2h.rdata = 32'b0;
            ibus_d2h.error = 1'b0;
        end else begin
            ibus_d2h = dev_d2h[ibus_dev];
        end

        // D-bus response
        if (!dbus_h2d.valid) begin
            dbus_d2h = `TL_D2H_DEFAULT;
        end else if (dbus_dev < 0) begin
            dbus_d2h = error_resp;
        end else if (contention && !dbus_grant) begin
            dbus_d2h.valid = 1'b0;
            dbus_d2h.ready = 1'b0;
            dbus_d2h.rdata = 32'b0;
            dbus_d2h.error = 1'b0;
        end else begin
            dbus_d2h = dev_d2h[dbus_dev];
        end
    end

endmodule
