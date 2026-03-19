// ============================================================================
// plic.sv — Platform-Level Interrupt Controller (simplified)
// ============================================================================
// 8 interrupt sources, 7 priority levels.
// Registers (word-aligned offsets from base 0x0C00_0000):
//   0x000..0x01C  Source 1..7 priority (source 0 reserved)
//   0x080         Pending bits [7:0]
//   0x100         Enable bits [7:0]
//   0x200         Priority threshold
//   0x204         Claim/complete (read=claim, write=complete)
// ============================================================================

`include "tl_ul_defs.svh"

module plic #(
    parameter int N_SRC = 8
)(
    input  logic              clk,
    input  logic              rst_n,

    // ── TL-UL device port ───────────────────────────────────────────────
    input  tl_h2d_t           tl_h2d,
    output tl_d2h_t           tl_d2h,

    // ── Interrupt sources ───────────────────────────────────────────────
    input  logic [N_SRC-1:0]  irq_sources,

    // ── Interrupt to CPU ────────────────────────────────────────────────
    output logic              ext_irq
);

    // ── Registers ───────────────────────────────────────────────────────
    logic [2:0] priority_r [0:N_SRC-1];  // 3-bit priority (0..7)
    logic [N_SRC-1:0] pending;
    logic [N_SRC-1:0] enable;
    logic [2:0] threshold;
    logic [3:0] claimed_id;  // 0 = none

    // ── Edge detection for interrupt sources ────────────────────────────
    logic [N_SRC-1:0] irq_prev;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq_prev <= '0;
        else
            irq_prev <= irq_sources;
    end

    // Set pending on rising edge
    integer k;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= '0;
        end else begin
            for (k = 0; k < N_SRC; k = k + 1) begin
                if (irq_sources[k] && !irq_prev[k])
                    pending[k] <= 1'b1;
            end
            // Clear pending on claim
            if (claimed_id != 4'd0)
                pending[claimed_id] <= 1'b0;
        end
    end

    // ── Find highest-priority pending & enabled interrupt ───────────────
    logic [3:0] best_id;
    logic [2:0] best_pri;

    integer j;
    always_comb begin
        best_id  = 4'd0;
        best_pri = 3'd0;
        for (j = 1; j < N_SRC; j = j + 1) begin
            if (pending[j] && enable[j] && (priority_r[j] > best_pri)) begin
                best_id  = j[3:0];
                best_pri = priority_r[j];
            end
        end
    end

    // CPU interrupt if best priority exceeds threshold
    assign ext_irq = (best_id != 4'd0) && (best_pri > threshold);

    // ── TL-UL register interface ────────────────────────────────────────
    logic [15:0] offset;
    assign offset = tl_h2d.addr[15:0];

    logic [31:0] rdata;
    logic rsp_valid;

    // Read
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata      <= 32'b0;
            rsp_valid  <= 1'b0;
            claimed_id <= 4'd0;
        end else begin
            rsp_valid  <= tl_h2d.valid && !tl_h2d.we;
            claimed_id <= 4'd0;

            if (tl_h2d.valid && !tl_h2d.we) begin
                if (offset < 16'h020) begin
                    // Priority registers (offset / 4 = source index)
                    rdata <= {29'b0, priority_r[offset[4:2]]};
                end else begin
                    case (offset)
                        16'h080: rdata <= {24'b0, pending};
                        16'h100: rdata <= {24'b0, enable};
                        16'h200: rdata <= {29'b0, threshold};
                        16'h204: begin
                            rdata      <= {28'b0, best_id};
                            claimed_id <= best_id;  // claim
                        end
                        default: rdata <= 32'b0;
                    endcase
                end
            end
        end
    end

    // Write
    integer m;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (m = 0; m < N_SRC; m = m + 1)
                priority_r[m] <= 3'd0;
            enable    <= '0;
            threshold <= 3'd0;
        end else if (tl_h2d.valid && tl_h2d.we) begin
            if (offset < 16'h020) begin
                priority_r[offset[4:2]] <= tl_h2d.wdata[2:0];
            end else begin
                case (offset)
                    16'h100: enable    <= tl_h2d.wdata[N_SRC-1:0];
                    16'h200: threshold <= tl_h2d.wdata[2:0];
                    16'h204: ;  // complete (write completes the claim — pending already cleared)
                    default: ;
                endcase
            end
        end
    end

    // TL-UL response
    assign tl_d2h.ready = 1'b1;
    assign tl_d2h.valid = rsp_valid;
    assign tl_d2h.rdata = rdata;
    assign tl_d2h.error = 1'b0;

endmodule
