// ============================================================================
// mem_stage.sv — Memory Access stage
// ============================================================================
// Generates TL-UL load/store requests with correct byte-enables.
// Handles sign/zero extension for LB/LBU/LH/LHU/LW on read data.
// ============================================================================

`include "rv32_defs.svh"
`include "tl_ul_defs.svh"

module mem_stage (
    // ── Control ─────────────────────────────────────────────────────────
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [2:0]  mem_funct3,     // F3_BYTE, F3_HALF, F3_WORD, etc.

    // ── Data from execute ───────────────────────────────────────────────
    input  logic [31:0] addr,           // ALU result = effective address
    input  logic [31:0] store_data,     // rs2 data for stores

    // ── TL-UL data bus (host side) ──────────────────────────────────────
    output tl_h2d_t     dmem_h2d,
    input  tl_d2h_t     dmem_d2h,

    // ── Load result ─────────────────────────────────────────────────────
    output logic [31:0] load_data,      // sign/zero-extended read data
    output logic        mem_busy        // stall if device not ready
);

    // ── Byte offset within the word ─────────────────────────────────────
    logic [1:0] byte_off;
    assign byte_off = addr[1:0];

    // ── Byte-enable generation ──────────────────────────────────────────
    logic [3:0] be;

    always_comb begin
        case (mem_funct3)
            `F3_BYTE, `F3_BYTEU: begin
                case (byte_off)
                    2'b00: be = 4'b0001;
                    2'b01: be = 4'b0010;
                    2'b10: be = 4'b0100;
                    2'b11: be = 4'b1000;
                endcase
            end
            `F3_HALF, `F3_HALFU: begin
                case (byte_off[1])
                    1'b0: be = 4'b0011;
                    1'b1: be = 4'b1100;
                endcase
            end
            default: be = 4'b1111;  // F3_WORD
        endcase
    end

    // ── Store data alignment ────────────────────────────────────────────
    // Shift store data to the correct byte lanes
    logic [31:0] aligned_wdata;

    always_comb begin
        case (mem_funct3)
            `F3_BYTE: begin
                case (byte_off)
                    2'b00: aligned_wdata = {24'b0, store_data[7:0]};
                    2'b01: aligned_wdata = {16'b0, store_data[7:0], 8'b0};
                    2'b10: aligned_wdata = {8'b0,  store_data[7:0], 16'b0};
                    2'b11: aligned_wdata = {store_data[7:0], 24'b0};
                endcase
            end
            `F3_HALF: begin
                case (byte_off[1])
                    1'b0: aligned_wdata = {16'b0, store_data[15:0]};
                    1'b1: aligned_wdata = {store_data[15:0], 16'b0};
                endcase
            end
            default: aligned_wdata = store_data;
        endcase
    end

    // ── Drive TL-UL ─────────────────────────────────────────────────────
    assign dmem_h2d.valid = mem_read || mem_write;
    assign dmem_h2d.we    = mem_write;
    assign dmem_h2d.addr  = {addr[31:2], 2'b00};  // word-aligned
    assign dmem_h2d.wdata = aligned_wdata;
    assign dmem_h2d.be    = be;

    // ── Stall if device is not ready ────────────────────────────────────
    assign mem_busy = (mem_read || mem_write) && !dmem_d2h.ready;

    // ── Load data extraction + sign/zero extension ──────────────────────
    logic [31:0] rdata;
    assign rdata = dmem_d2h.rdata;

    always_comb begin
        case (mem_funct3)
            `F3_BYTE: begin
                case (byte_off)
                    2'b00: load_data = {{24{rdata[7]}},  rdata[7:0]};
                    2'b01: load_data = {{24{rdata[15]}}, rdata[15:8]};
                    2'b10: load_data = {{24{rdata[23]}}, rdata[23:16]};
                    2'b11: load_data = {{24{rdata[31]}}, rdata[31:24]};
                endcase
            end
            `F3_BYTEU: begin
                case (byte_off)
                    2'b00: load_data = {24'b0, rdata[7:0]};
                    2'b01: load_data = {24'b0, rdata[15:8]};
                    2'b10: load_data = {24'b0, rdata[23:16]};
                    2'b11: load_data = {24'b0, rdata[31:24]};
                endcase
            end
            `F3_HALF: begin
                case (byte_off[1])
                    1'b0: load_data = {{16{rdata[15]}}, rdata[15:0]};
                    1'b1: load_data = {{16{rdata[31]}}, rdata[31:16]};
                endcase
            end
            `F3_HALFU: begin
                case (byte_off[1])
                    1'b0: load_data = {16'b0, rdata[15:0]};
                    1'b1: load_data = {16'b0, rdata[31:16]};
                endcase
            end
            default: load_data = rdata;  // F3_WORD
        endcase
    end

endmodule
