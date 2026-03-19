// ============================================================================
// compressed_decoder.sv — RV32C → RV32I instruction expander
// ============================================================================
// If instr[1:0] != 2'b11, this is a 16-bit C-extension instruction.
// Expand it to the equivalent 32-bit RV32I encoding.
// Otherwise, pass through unchanged.
//
// Covers the full RV32C quadrant 0, 1, and 2 instruction set.
// ============================================================================

`include "rv32_defs.svh"

module compressed_decoder (
    input  logic [31:0] instr_i,      // raw instruction (16-bit in [15:0])
    output logic [31:0] instr_o,      // expanded 32-bit instruction
    output logic        is_compressed, // 1 = was 16-bit
    output logic        illegal_c     // 1 = unrecognized C-encoding
);

    logic [15:0] ci;
    assign ci = instr_i[15:0];

    // Compressed register mapping: cr' = cr + 8 (registers x8..x15)
    logic [4:0] rs1_p, rs2_p, rd_p;
    assign rs1_p = {2'b01, ci[9:7]};
    assign rs2_p = {2'b01, ci[4:2]};
    assign rd_p  = {2'b01, ci[4:2]};

    assign is_compressed = (ci[1:0] != 2'b11);

    always_comb begin
        instr_o   = instr_i;  // default: pass through
        illegal_c = 1'b0;

        if (is_compressed) begin
            case (ci[1:0])
                // ────────────────────────────────────────────────
                // Quadrant 0 (C0)
                // ────────────────────────────────────────────────
                2'b00: begin
                    case (ci[15:13])
                        3'b000: begin // C.ADDI4SPN  → addi rd', x2, nzuimm
                            if (ci[12:5] == 8'b0) begin
                                illegal_c = 1'b1;
                                instr_o   = 32'b0;
                            end else begin
                                // nzuimm = {ci[10:7], ci[12:11], ci[5], ci[6], 2'b00}
                                instr_o = {2'b0, ci[10:7], ci[12:11], ci[5], ci[6], 2'b00,
                                           5'd2, 3'b000, rd_p, 7'b0010011};
                            end
                        end
                        3'b010: begin // C.LW → lw rd', offset(rs1')
                            // offset = {ci[5], ci[12:10], ci[6], 2'b00}
                            instr_o = {5'b0, ci[5], ci[12:10], ci[6], 2'b00,
                                       rs1_p, 3'b010, rd_p, 7'b0000011};
                        end
                        3'b110: begin // C.SW → sw rs2', offset(rs1')
                            // offset = {ci[5], ci[12:10], ci[6], 2'b00}
                            instr_o = {5'b0, ci[5], ci[12], rs2_p, rs1_p,
                                       3'b010, ci[11:10], ci[6], 2'b00, 7'b0100011};
                        end
                        default: begin
                            illegal_c = 1'b1;
                            instr_o   = 32'b0;
                        end
                    endcase
                end

                // ────────────────────────────────────────────────
                // Quadrant 1 (C1)
                // ────────────────────────────────────────────────
                2'b01: begin
                    case (ci[15:13])
                        3'b000: begin // C.NOP / C.ADDI → addi rd, rd, nzimm
                            instr_o = {{6{ci[12]}}, ci[12], ci[6:2],
                                       ci[11:7], 3'b000, ci[11:7], 7'b0010011};
                        end
                        3'b001: begin // C.JAL → jal x1, offset
                            // offset[11|4|9:8|10|6|7|3:1|5]
                            instr_o = {ci[12], ci[8], ci[10:9], ci[6],
                                       ci[7], ci[2], ci[11], ci[5:3],
                                       {9{ci[12]}}, 5'd1, 7'b1101111};
                        end
                        3'b010: begin // C.LI → addi rd, x0, imm
                            instr_o = {{6{ci[12]}}, ci[12], ci[6:2],
                                       5'd0, 3'b000, ci[11:7], 7'b0010011};
                        end
                        3'b011: begin
                            if (ci[11:7] == 5'd2) begin // C.ADDI16SP → addi x2, x2, nzimm
                                if ({ci[12], ci[6:2]} == 6'b0) begin
                                    illegal_c = 1'b1;
                                    instr_o   = 32'b0;
                                end else begin
                                    // nzimm = {ci[12], ci[4:3], ci[5], ci[2], ci[6], 4'b0000}
                                    instr_o = {{2{ci[12]}}, ci[12], ci[4:3], ci[5], ci[2], ci[6],
                                               4'b0000, 5'd2, 3'b000, 5'd2, 7'b0010011};
                                end
                            end else begin // C.LUI → lui rd, nzimm
                                if ({ci[12], ci[6:2]} == 6'b0) begin
                                    illegal_c = 1'b1;
                                    instr_o   = 32'b0;
                                end else begin
                                    instr_o = {{14{ci[12]}}, ci[12], ci[6:2],
                                               ci[11:7], 7'b0110111};
                                end
                            end
                        end
                        3'b100: begin
                            case (ci[11:10])
                                2'b00: begin // C.SRLI → srli rd', rd', shamt
                                    instr_o = {7'b0000000, ci[6:2],
                                               rs1_p, 3'b101, rs1_p, 7'b0010011};
                                end
                                2'b01: begin // C.SRAI → srai rd', rd', shamt
                                    instr_o = {7'b0100000, ci[6:2],
                                               rs1_p, 3'b101, rs1_p, 7'b0010011};
                                end
                                2'b10: begin // C.ANDI → andi rd', rd', imm
                                    instr_o = {{6{ci[12]}}, ci[12], ci[6:2],
                                               rs1_p, 3'b111, rs1_p, 7'b0010011};
                                end
                                2'b11: begin
                                    case ({ci[12], ci[6:5]})
                                        3'b000: // C.SUB → sub rd', rd', rs2'
                                            instr_o = {7'b0100000, rs2_p,
                                                       rs1_p, 3'b000, rs1_p, 7'b0110011};
                                        3'b001: // C.XOR → xor rd', rd', rs2'
                                            instr_o = {7'b0000000, rs2_p,
                                                       rs1_p, 3'b100, rs1_p, 7'b0110011};
                                        3'b010: // C.OR → or rd', rd', rs2'
                                            instr_o = {7'b0000000, rs2_p,
                                                       rs1_p, 3'b110, rs1_p, 7'b0110011};
                                        3'b011: // C.AND → and rd', rd', rs2'
                                            instr_o = {7'b0000000, rs2_p,
                                                       rs1_p, 3'b111, rs1_p, 7'b0110011};
                                        default: begin
                                            illegal_c = 1'b1;
                                            instr_o   = 32'b0;
                                        end
                                    endcase
                                end
                            endcase
                        end
                        3'b101: begin // C.J → jal x0, offset
                            instr_o = {ci[12], ci[8], ci[10:9], ci[6],
                                       ci[7], ci[2], ci[11], ci[5:3],
                                       {9{ci[12]}}, 5'd0, 7'b1101111};
                        end
                        3'b110: begin // C.BEQZ → beq rs1', x0, offset
                            instr_o = {{3{ci[12]}}, ci[12], ci[6:5], ci[2],
                                       5'd0, rs1_p, 3'b000,
                                       ci[11:10], ci[4:3], ci[12], 7'b1100011};
                        end
                        3'b111: begin // C.BNEZ → bne rs1', x0, offset
                            instr_o = {{3{ci[12]}}, ci[12], ci[6:5], ci[2],
                                       5'd0, rs1_p, 3'b001,
                                       ci[11:10], ci[4:3], ci[12], 7'b1100011};
                        end
                    endcase
                end

                // ────────────────────────────────────────────────
                // Quadrant 2 (C2)
                // ────────────────────────────────────────────────
                2'b10: begin
                    case (ci[15:13])
                        3'b000: begin // C.SLLI → slli rd, rd, shamt
                            instr_o = {7'b0000000, ci[6:2],
                                       ci[11:7], 3'b001, ci[11:7], 7'b0010011};
                        end
                        3'b010: begin // C.LWSP → lw rd, offset(x2)
                            if (ci[11:7] == 5'b0) begin
                                illegal_c = 1'b1;
                                instr_o   = 32'b0;
                            end else begin
                                // offset = {ci[3:2], ci[12], ci[6:4], 2'b00}
                                instr_o = {4'b0, ci[3:2], ci[12], ci[6:4], 2'b00,
                                           5'd2, 3'b010, ci[11:7], 7'b0000011};
                            end
                        end
                        3'b100: begin
                            if (ci[12] == 1'b0) begin
                                if (ci[6:2] == 5'b0) begin // C.JR → jalr x0, rs1, 0
                                    if (ci[11:7] == 5'b0) begin
                                        illegal_c = 1'b1;
                                        instr_o   = 32'b0;
                                    end else begin
                                        instr_o = {12'b0, ci[11:7], 3'b000, 5'd0, 7'b1100111};
                                    end
                                end else begin // C.MV → add rd, x0, rs2
                                    instr_o = {7'b0000000, ci[6:2],
                                               5'd0, 3'b000, ci[11:7], 7'b0110011};
                                end
                            end else begin
                                if (ci[6:2] == 5'b0) begin
                                    if (ci[11:7] == 5'b0) begin // C.EBREAK → ebreak
                                        instr_o = 32'b000000000001_00000_000_00000_1110011;
                                    end else begin // C.JALR → jalr x1, rs1, 0
                                        instr_o = {12'b0, ci[11:7], 3'b000, 5'd1, 7'b1100111};
                                    end
                                end else begin // C.ADD → add rd, rd, rs2
                                    instr_o = {7'b0000000, ci[6:2],
                                               ci[11:7], 3'b000, ci[11:7], 7'b0110011};
                                end
                            end
                        end
                        3'b110: begin // C.SWSP → sw rs2, offset(x2)
                            // offset = {ci[8:7], ci[12:9], 2'b00}
                            instr_o = {4'b0, ci[8:7], ci[12], ci[6:2],
                                       5'd2, 3'b010, ci[11:9], 2'b00, 7'b0100011};
                        end
                        default: begin
                            illegal_c = 1'b1;
                            instr_o   = 32'b0;
                        end
                    endcase
                end

                default: begin
                    // Should not happen (ci[1:0] == 2'b11 is filtered by is_compressed)
                    instr_o   = instr_i;
                    illegal_c = 1'b0;
                end
            endcase
        end
    end

endmodule
