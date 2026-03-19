// ============================================================================
// clint.sv — Core Local Interruptor
// ============================================================================
// Provides machine timer (mtime/mtimecmp) and software interrupt (msip).
// Registers (word-aligned offsets from base 0x0200_0000):
//   0x0000  msip       [0] software interrupt pending
//   0x4000  mtimecmp   [31:0] lower 32 bits
//   0x4004  mtimecmph  [31:0] upper 32 bits
//   0xBFF8  mtime      [31:0] lower 32 bits
//   0xBFFC  mtimeh     [31:0] upper 32 bits
// ============================================================================

`include "tl_ul_defs.svh"

module clint (
    input  logic        clk,
    input  logic        rst_n,

    // ── TL-UL device port ───────────────────────────────────────────────
    input  tl_h2d_t     tl_h2d,
    output tl_d2h_t     tl_d2h,

    // ── Interrupts to CPU ───────────────────────────────────────────────
    output logic        timer_irq,
    output logic        sw_irq
);

    // ── Registers ───────────────────────────────────────────────────────
    logic [63:0] mtime;
    logic [63:0] mtimecmp;
    logic        msip;

    // ── Timer: free-running counter ─────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mtime <= 64'b0;
        else
            mtime <= mtime + 64'd1;
    end

    // ── Interrupt generation ────────────────────────────────────────────
    assign timer_irq = (mtime >= mtimecmp);
    assign sw_irq    = msip;

    // ── TL-UL register interface ────────────────────────────────────────
    logic [15:0] offset;
    assign offset = tl_h2d.addr[15:0];

    logic [31:0] rdata;
    logic rsp_valid;

    // Read
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata     <= 32'b0;
            rsp_valid <= 1'b0;
        end else begin
            rsp_valid <= tl_h2d.valid && !tl_h2d.we;
            if (tl_h2d.valid && !tl_h2d.we) begin
                case (offset)
                    16'h0000: rdata <= {31'b0, msip};
                    16'h4000: rdata <= mtimecmp[31:0];
                    16'h4004: rdata <= mtimecmp[63:32];
                    16'hBFF8: rdata <= mtime[31:0];
                    16'hBFFC: rdata <= mtime[63:32];
                    default:  rdata <= 32'b0;
                endcase
            end
        end
    end

    // Write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip     <= 1'b0;
            mtimecmp <= 64'hFFFFFFFF_FFFFFFFF;  // no timer IRQ on reset
        end else if (tl_h2d.valid && tl_h2d.we) begin
            case (offset)
                16'h0000: msip             <= tl_h2d.wdata[0];
                16'h4000: mtimecmp[31:0]   <= tl_h2d.wdata;
                16'h4004: mtimecmp[63:32]  <= tl_h2d.wdata;
                // mtime is read-only in this implementation
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
