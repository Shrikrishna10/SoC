// ============================================================================
// writeback.sv — Writeback stage
// ============================================================================
// Selects the final value to write to the register file based on wb_sel.
// Sources: ALU result, memory load, PC+4 (link), CSR read, MulDiv result.
// ============================================================================

`include "rv32_defs.svh"

module writeback (
    input  wb_sel_t     wb_sel,

    input  logic [31:0] alu_result,
    input  logic [31:0] mem_data,
    input  logic [31:0] pc_plus_4,
    input  logic [31:0] csr_rdata,
    input  logic [31:0] muldiv_result,

    output logic [31:0] wb_data
);

    always_comb begin
        case (wb_sel)
            WB_ALU:    wb_data = alu_result;
            WB_MEM:    wb_data = mem_data;
            WB_PC4:    wb_data = pc_plus_4;
            WB_CSR:    wb_data = csr_rdata;
            WB_MULDIV: wb_data = muldiv_result;
            default:   wb_data = 32'b0;
        endcase
    end

endmodule
