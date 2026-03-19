// ============================================================================
// tb_regfile.sv — Register file testbench
// ============================================================================

`include "rv32_defs.svh"

module tb_regfile;

    logic        clk, rst_n;
    logic        wr_en;
    logic [4:0]  wr_addr;
    logic [31:0] wr_data;
    logic [4:0]  rd_addr_a, rd_addr_b;
    logic [31:0] rd_data_a, rd_data_b;

    regfile uut (.*);

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count, fail_count;

    task automatic check(input string name, input logic [31:0] exp_a, input logic [31:0] exp_b);
        @(negedge clk);
        if (rd_data_a !== exp_a) begin
            $display("FAIL %s port_a: got=%h exp=%h", name, rd_data_a, exp_a);
            fail_count = fail_count + 1;
        end else pass_count = pass_count + 1;
        if (rd_data_b !== exp_b) begin
            $display("FAIL %s port_b: got=%h exp=%h", name, rd_data_b, exp_b);
            fail_count = fail_count + 1;
        end else pass_count = pass_count + 1;
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        rst_n = 0; wr_en = 0; wr_addr = 0; wr_data = 0;
        rd_addr_a = 0; rd_addr_b = 0;
        @(posedge clk); #1;
        rst_n = 1;

        // ── Test 1: x0 is always zero ───────────────────────────────────
        wr_en = 1; wr_addr = 5'd0; wr_data = 32'hDEADBEEF;
        @(posedge clk); #1;
        wr_en = 0;
        rd_addr_a = 5'd0; rd_addr_b = 5'd0;
        check("x0 hardwired", 32'b0, 32'b0);

        // ── Test 2: Write and read back ─────────────────────────────────
        wr_en = 1; wr_addr = 5'd1; wr_data = 32'hCAFEBABE;
        @(posedge clk); #1;
        wr_en = 0;
        rd_addr_a = 5'd1; rd_addr_b = 5'd0;
        check("write x1", 32'hCAFEBABE, 32'b0);

        // ── Test 3: Two different registers ─────────────────────────────
        wr_en = 1; wr_addr = 5'd15; wr_data = 32'h12345678;
        @(posedge clk); #1;
        wr_en = 0;
        rd_addr_a = 5'd1; rd_addr_b = 5'd15;
        check("two regs", 32'hCAFEBABE, 32'h12345678);

        // ── Test 4: Write-first forwarding ──────────────────────────────
        wr_en = 1; wr_addr = 5'd7; wr_data = 32'hAAAA_BBBB;
        rd_addr_a = 5'd7; rd_addr_b = 5'd1;
        // On same cycle: reading x7 while writing x7
        @(negedge clk);
        if (rd_data_a !== 32'hAAAA_BBBB) begin
            $display("FAIL write-fwd: got=%h exp=%h", rd_data_a, 32'hAAAA_BBBB);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end

        @(posedge clk); #1;
        wr_en = 0;

        // ── Test 5: Write all registers, read back ──────────────────────
        for (int i = 1; i < 32; i++) begin
            wr_en = 1; wr_addr = i[4:0]; wr_data = i;
            @(posedge clk); #1;
        end
        wr_en = 0;

        for (int i = 1; i < 32; i++) begin
            rd_addr_a = i[4:0]; rd_addr_b = 5'd0;
            @(negedge clk);
            if (rd_data_a !== i[31:0]) begin
                $display("FAIL x%0d: got=%h exp=%h", i, rd_data_a, i[31:0]);
                fail_count = fail_count + 1;
            end else pass_count = pass_count + 1;
        end

        // ── Test 6: Reset clears all ────────────────────────────────────
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        rd_addr_a = 5'd1; rd_addr_b = 5'd15;
        check("post-reset", 32'b0, 32'b0);

        $display("\n=== REGFILE TB: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
