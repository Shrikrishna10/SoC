// ============================================================================
// tb_alu.sv — ALU testbench
// ============================================================================

`include "rv32_defs.svh"

module tb_alu;

    logic [31:0] a, b, result;
    alu_op_t     op;
    logic        cmp_eq, cmp_lt, cmp_ltu;

    alu uut (.*);

    integer pass_count, fail_count;

    task automatic check(
        input string     name,
        input logic [31:0] expected,
        input logic        exp_eq  = 1'bx,
        input logic        exp_lt  = 1'bx,
        input logic        exp_ltu = 1'bx
    );
        #1;
        if (result !== expected) begin
            $display("FAIL %s: a=%h b=%h result=%h expected=%h", name, a, b, result, expected);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end
        if (exp_eq !== 1'bx && cmp_eq !== exp_eq) begin
            $display("FAIL %s cmp_eq: got=%b expected=%b", name, cmp_eq, exp_eq);
            fail_count = fail_count + 1;
        end
        if (exp_lt !== 1'bx && cmp_lt !== exp_lt) begin
            $display("FAIL %s cmp_lt: got=%b expected=%b", name, cmp_lt, exp_lt);
            fail_count = fail_count + 1;
        end
        if (exp_ltu !== 1'bx && cmp_ltu !== exp_ltu) begin
            $display("FAIL %s cmp_ltu: got=%b expected=%b", name, cmp_ltu, exp_ltu);
            fail_count = fail_count + 1;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        // ADD
        a = 32'd10; b = 32'd20; op = ALU_ADD; check("ADD basic", 32'd30);
        a = 32'hFFFFFFFF; b = 32'd1; op = ALU_ADD; check("ADD overflow", 32'd0);

        // SUB
        a = 32'd20; b = 32'd10; op = ALU_SUB; check("SUB basic", 32'd10);
        a = 32'd0; b = 32'd1; op = ALU_SUB; check("SUB underflow", 32'hFFFFFFFF);

        // AND / OR / XOR
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; op = ALU_AND; check("AND", 32'h0F000F00);
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; op = ALU_OR;  check("OR",  32'hFF0FFF0F);
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; op = ALU_XOR; check("XOR", 32'hF00FF00F);

        // Shifts
        a = 32'h0000_0001; b = 32'd4; op = ALU_SLL; check("SLL", 32'h0000_0010);
        a = 32'h8000_0000; b = 32'd4; op = ALU_SRL; check("SRL", 32'h0800_0000);
        a = 32'h8000_0000; b = 32'd4; op = ALU_SRA; check("SRA", 32'hF800_0000);
        a = 32'h7000_0000; b = 32'd4; op = ALU_SRA; check("SRA pos", 32'h0700_0000);

        // SLT / SLTU
        a = -32'sd5; b = 32'd3; op = ALU_SLT;  check("SLT neg<pos",  32'd1);
        a = 32'd3;   b = -32'sd5; op = ALU_SLT; check("SLT pos>neg", 32'd0);
        a = 32'd3;   b = 32'd5;   op = ALU_SLTU; check("SLTU 3<5",   32'd1);
        a = 32'hFFFFFFFF; b = 32'd1; op = ALU_SLTU; check("SLTU max>1", 32'd0);

        // PASS_B
        a = 32'hDEAD; b = 32'hBEEF; op = ALU_PASS_B; check("PASS_B", 32'hBEEF);

        // Comparison flags
        a = 32'd42; b = 32'd42; op = ALU_SUB;
        check("EQ flags", 32'd0, .exp_eq(1'b1), .exp_lt(1'b0), .exp_ltu(1'b0));

        a = -32'sd1; b = 32'd1; op = ALU_SUB;
        check("NEG flags", 32'hFFFFFFFE, .exp_eq(1'b0), .exp_lt(1'b1), .exp_ltu(1'b0));

        $display("\n=== ALU TB: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
