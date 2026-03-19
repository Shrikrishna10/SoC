// ============================================================================
// muldiv.sv — RV32M multiply/divide unit (iterative, multi-cycle)
// ============================================================================
// No operator usage for mul/div — uses shift-and-add for multiply,
// restoring division for divide.
//
// Interface: start pulse, busy/valid handshake.
// Multiply: 32 cycles (shift-and-add, 1 bit per cycle)
// Divide:   32 cycles (restoring divider, 1 bit per cycle)
// ============================================================================

`include "rv32_defs.svh"

module muldiv (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  muldiv_op_t  op,
    input  logic        start,       // pulse to begin operation

    output logic [31:0] result,
    output logic        busy,        // 1 while computing
    output logic        valid        // 1 for one cycle when result is ready
);

    // ── State ────────────────────────────────────────────────────────────
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        CALC  = 2'b01,
        DONE  = 2'b10
    } state_t;

    state_t state, state_next;

    // ── Internal registers ───────────────────────────────────────────────
    logic [63:0] accumulator;    // 64-bit product / {remainder, quotient}
    logic [31:0] op_b_abs;       // absolute value of operand B
    logic [5:0]  count;          // cycle counter (0..31)
    logic        is_div;         // 1 if division operation
    logic        negate_result;  // 1 if final result needs negation
    logic        negate_rem;     // 1 if remainder needs negation
    logic        return_hi;      // 1 to return upper 32 bits (MULH* / REM*)

    // ── Absolute value helper (negate via invert + 1) ────────────────────
    function automatic [31:0] abs_val(input [31:0] val);
        abs_val = val[31] ? (~val + 32'd1) : val;
    endfunction

    // ── Combinational next-state logic ───────────────────────────────────
    always_comb begin
        state_next = state;
        case (state)
            IDLE:    if (start) state_next = CALC;
            CALC:    if (count == 6'd31) state_next = DONE;
            DONE:    state_next = IDLE;
            default: state_next = IDLE;
        endcase
    end

    // ── Sequential datapath ──────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            accumulator    <= 64'b0;
            op_b_abs       <= 32'b0;
            count          <= 6'b0;
            is_div         <= 1'b0;
            negate_result  <= 1'b0;
            negate_rem     <= 1'b0;
            return_hi      <= 1'b0;
        end else begin
            state <= state_next;

            case (state)
                IDLE: begin
                    if (start) begin
                        count <= 6'd0;

                        case (op)
                            // ── Multiply operations ──────────────────
                            MD_MUL: begin
                                // Unsigned multiply of both operands
                                // (result is the same for signed MUL low word)
                                accumulator   <= {32'b0, operand_a};
                                op_b_abs      <= operand_b;
                                is_div        <= 1'b0;
                                negate_result <= 1'b0;
                                return_hi     <= 1'b0;
                            end
                            MD_MULH: begin
                                // Signed × Signed → upper 32
                                accumulator   <= {32'b0, abs_val(operand_a)};
                                op_b_abs      <= abs_val(operand_b);
                                is_div        <= 1'b0;
                                negate_result <= operand_a[31] ^ operand_b[31];
                                return_hi     <= 1'b1;
                            end
                            MD_MULHSU: begin
                                // Signed × Unsigned → upper 32
                                accumulator   <= {32'b0, abs_val(operand_a)};
                                op_b_abs      <= operand_b;
                                is_div        <= 1'b0;
                                negate_result <= operand_a[31];
                                return_hi     <= 1'b1;
                            end
                            MD_MULHU: begin
                                // Unsigned × Unsigned → upper 32
                                accumulator   <= {32'b0, operand_a};
                                op_b_abs      <= operand_b;
                                is_div        <= 1'b0;
                                negate_result <= 1'b0;
                                return_hi     <= 1'b1;
                            end
                            // ── Division operations ──────────────────
                            MD_DIV: begin
                                if (operand_b == 32'b0) begin
                                    // Division by zero: result = -1
                                    accumulator   <= {32'b0, 32'hFFFFFFFF};
                                    op_b_abs      <= 32'b0;
                                    is_div        <= 1'b0; // skip calc, go to DONE
                                    negate_result <= 1'b0;
                                    return_hi     <= 1'b0;
                                end else begin
                                    accumulator   <= {32'b0, abs_val(operand_a)};
                                    op_b_abs      <= abs_val(operand_b);
                                    is_div        <= 1'b1;
                                    negate_result <= operand_a[31] ^ operand_b[31];
                                    negate_rem    <= operand_a[31];
                                    return_hi     <= 1'b0;
                                end
                            end
                            MD_DIVU: begin
                                if (operand_b == 32'b0) begin
                                    accumulator   <= {32'b0, 32'hFFFFFFFF};
                                    op_b_abs      <= 32'b0;
                                    is_div        <= 1'b0;
                                    negate_result <= 1'b0;
                                    return_hi     <= 1'b0;
                                end else begin
                                    accumulator   <= {32'b0, operand_a};
                                    op_b_abs      <= operand_b;
                                    is_div        <= 1'b1;
                                    negate_result <= 1'b0;
                                    negate_rem    <= 1'b0;
                                    return_hi     <= 1'b0;
                                end
                            end
                            MD_REM: begin
                                if (operand_b == 32'b0) begin
                                    // Remainder of div-by-zero = dividend
                                    accumulator   <= {32'b0, operand_a};
                                    op_b_abs      <= 32'b0;
                                    is_div        <= 1'b0;
                                    negate_result <= 1'b0;
                                    return_hi     <= 1'b0;
                                end else begin
                                    accumulator   <= {32'b0, abs_val(operand_a)};
                                    op_b_abs      <= abs_val(operand_b);
                                    is_div        <= 1'b1;
                                    negate_result <= operand_a[31]; // rem sign = dividend sign
                                    negate_rem    <= operand_a[31];
                                    return_hi     <= 1'b1;          // remainder in upper half
                                end
                            end
                            MD_REMU: begin
                                if (operand_b == 32'b0) begin
                                    accumulator   <= {32'b0, operand_a};
                                    op_b_abs      <= 32'b0;
                                    is_div        <= 1'b0;
                                    negate_result <= 1'b0;
                                    return_hi     <= 1'b0;
                                end else begin
                                    accumulator   <= {32'b0, operand_a};
                                    op_b_abs      <= operand_b;
                                    is_div        <= 1'b1;
                                    negate_result <= 1'b0;
                                    negate_rem    <= 1'b0;
                                    return_hi     <= 1'b1;
                                end
                            end
                            default: begin
                                accumulator   <= 64'b0;
                                op_b_abs      <= 32'b0;
                                is_div        <= 1'b0;
                                negate_result <= 1'b0;
                                return_hi     <= 1'b0;
                            end
                        endcase
                    end
                end

                CALC: begin
                    count <= count + 6'd1;

                    if (is_div) begin
                        // ── Restoring division: 1 bit per cycle ──
                        // Shift accumulator left by 1, bring in 0
                        // Upper half = remainder candidate, lower = quotient
                        logic [63:0] shifted;
                        logic [32:0] trial_sub;

                        shifted   = {accumulator[62:0], 1'b0};
                        trial_sub = {1'b0, shifted[63:32]} + {1'b0, ~op_b_abs} + 33'd1;

                        if (!trial_sub[32]) begin
                            // Subtraction succeeded: remainder >= 0
                            accumulator <= {trial_sub[31:0], shifted[31:1], 1'b1};
                        end else begin
                            // Restore: keep shifted value, quotient bit = 0
                            accumulator <= shifted;
                        end
                    end else begin
                        // ── Shift-and-add multiplication: 1 bit per cycle ──
                        // Check LSB of lower half; if 1, add op_b to upper half
                        if (accumulator[0]) begin
                            accumulator <= {1'b0, accumulator[63:32] + op_b_abs,
                                            accumulator[31:1]};
                        end else begin
                            accumulator <= {1'b0, accumulator[63:1]};
                        end
                    end
                end

                DONE: begin
                    // Result available for 1 cycle
                end

                default: ;
            endcase
        end
    end

    // ── Output logic ─────────────────────────────────────────────────────
    assign busy  = (state == CALC);
    assign valid = (state == DONE);

    // Select upper or lower 32 bits and apply sign correction
    logic [31:0] raw_result;

    always_comb begin
        if (return_hi)
            raw_result = accumulator[63:32];
        else
            raw_result = accumulator[31:0];

        // For division: upper=remainder, lower=quotient
        // negate_result applies to quotient (DIV) or remainder (REM)
        if (negate_result)
            result = ~raw_result + 32'd1;
        else
            result = raw_result;
    end

endmodule
