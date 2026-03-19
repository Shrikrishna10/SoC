// ============================================================================
// regfile.sv — 32×32-bit RISC-V register file
// ============================================================================
// x0 hardwired to zero. Two asynchronous read ports, one synchronous write.
// Write-first forwarding: if reading and writing the same register in the
// same cycle, the NEW value is returned (avoids a 1-cycle stale read).
// ============================================================================

`include "rv32_defs.svh"

module regfile (
    input  logic        clk,
    input  logic        rst_n,

    // Write port
    input  logic        wr_en,
    input  logic [4:0]  wr_addr,
    input  logic [31:0] wr_data,

    // Read port A
    input  logic [4:0]  rd_addr_a,
    output logic [31:0] rd_data_a,

    // Read port B
    input  logic [4:0]  rd_addr_b,
    output logic [31:0] rd_data_b
);

    logic [31:0] regs [1:31];  // x1..x31 (x0 is implicit zero)

    // ── Write (synchronous) ─────────────────────────────────────────────
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (wr_en && (wr_addr != 5'b0)) begin
            regs[wr_addr] <= wr_data;
        end
    end

    // ── Read with write-first forwarding (combinational) ────────────────
    assign rd_data_a = (rd_addr_a == 5'b0) ? 32'b0 :
                       (wr_en && (rd_addr_a == wr_addr)) ? wr_data :
                       regs[rd_addr_a];

    assign rd_data_b = (rd_addr_b == 5'b0) ? 32'b0 :
                       (wr_en && (rd_addr_b == wr_addr)) ? wr_data :
                       regs[rd_addr_b];

endmodule
