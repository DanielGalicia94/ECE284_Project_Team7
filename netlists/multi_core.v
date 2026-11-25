`timescale 1ns / 1ps
/*
multi_core: multi_corelet plus one activation/weight SRAM and one psum SRAM per core.
All SRAMs use the same address and control fields of the instruction, only the data differ per core.
D_xmem[c*32 +: 32] and sfp_out[c*128 +: 128] belong to core c, inst[34] is the cross-core reduction.
*/
module multi_core (clk, D_xmem, sfp_out, inst, reset, ofifo_valid);

parameter NI      = 2;
parameter NO      = 2;
parameter col     = 8;
parameter row     = 8;
parameter bw      = 4;
parameter bw_psum = 2*bw+8;
localparam NC     = NI*NO;
localparam XW     = row*bw;
localparam PW     = col*bw_psum;

input               clk;
input               reset;
input  [34:0]       inst;
input  [NC*XW-1:0]  D_xmem;
output [NC*PW-1:0]  sfp_out;
output              ofifo_valid;

wire [NC*XW-1:0] xmem_out;
wire [NC*PW-1:0] pmem_out;
wire [NC*PW-1:0] corelet_out;
wire [NC*PW-1:0] fifo_out;

// shared SRAM control (same fields as core.v)
wire        xmem_CEN = inst[19];
wire        xmem_WEN = inst[18];
wire [10:0] xmem_add = inst[17:7];
wire        pmem_CEN = inst[32];
wire        pmem_WEN = inst[31];
wire [10:0] pmem_add = inst[30:20];

assign sfp_out = corelet_out;

genvar c;
generate
  for (c = 0; c < NC; c = c + 1) begin : g_core
    wire [PW-1:0] pmem_in = inst[6] ? fifo_out[c*PW +: PW] : corelet_out[c*PW +: PW];

    sram_32b_w2048 xmem_inst (
      .CLK(clk), .D(D_xmem[c*XW +: XW]), .Q(xmem_out[c*XW +: XW]),
      .CEN(xmem_CEN), .WEN(xmem_WEN), .A(xmem_add));

    sram_128b_w2048 pmem_inst (
      .CLK(clk), .D(pmem_in), .Q(pmem_out[c*PW +: PW]),
      .CEN(pmem_CEN), .WEN(pmem_WEN), .A(pmem_add));
  end
endgenerate

multi_corelet #(.NI(NI), .NO(NO), .bw(bw), .bw_psum(bw_psum), .col(col), .row(row)) multi_corelet_inst (
  .clk        (clk),
  .reset      (reset),
  .inst       (inst),
  .l0_in      (xmem_out),
  .sfp_in     (pmem_out),
  .out        (corelet_out),
  .ofifo_valid(ofifo_valid),
  .fifo_out   (fifo_out)
);

endmodule
