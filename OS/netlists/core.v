// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission
// core.v -- Output Stationary version
module core (clk, D_xmem, sfp_out, inst, reset, ofifo_valid);

parameter col = 8;
parameter row = 8;
parameter bw = 4;
parameter bw_psum = 2*bw+8;

input  [row*bw-1:0] D_xmem;      // write data for activation SRAM AND weight SRAM
input  clk;
input  [47:0] inst;
input  reset;
output [bw_psum*col-1:0] sfp_out; // psum SRAM read data (for verification)
output ofifo_valid;

wire  [row*bw-1:0]      xmem_out;     // activation SRAM Q -> corelet l0_in
wire  [col*bw-1:0]      wmem_out;     // weight SRAM Q     -> corelet w_in
wire  [bw_psum*col-1:0] pmem_in;      // corelet out       -> psum SRAM D
wire  [bw_psum*col-1:0] pmem_out;     // psum SRAM Q       -> sfp_out
wire  [bw_psum*col-1:0] corelet_out;
wire  [bw_psum*col-1:0] fifo_out;

wire  [10:0] xmem_add, wmem_add, pmem_add;
wire  xmem_CEN, xmem_WEN;
wire  wmem_CEN, wmem_WEN;
wire  pmem_CEN, pmem_WEN;

// instruction fields
//  [47:37] wmem_add  [36] wmem_WEN  [35] wmem_CEN  [34] drain  [33] unused
//  [32] pmem_CEN  [31] pmem_WEN  [30:20] pmem_add
//  [19] xmem_CEN  [18] xmem_WEN  [17:7] xmem_add
//  [6] fifo_rd  [5] ififo_wr  [4] ififo_rd  [3] l0_rd  [2] l0_wr  [1] execute  [0] unused
assign wmem_add = inst[47:37];
assign wmem_WEN = inst[36];
assign wmem_CEN = inst[35];
assign pmem_CEN = inst[32];
assign pmem_WEN = inst[31];
assign pmem_add = inst[30:20];
assign xmem_CEN = inst[19];
assign xmem_WEN = inst[18];
assign xmem_add = inst[17:7];

assign pmem_in = corelet_out;     // ReLU'd output from OFIFO -> psum SRAM
assign sfp_out = pmem_out;        // read psum SRAM to check results

sram_32b_w2048 activation_mem_instance (
        .CLK(clk), .D(D_xmem), .Q(xmem_out),
        .CEN(xmem_CEN), .WEN(xmem_WEN), .A(xmem_add));

sram_32b_w2048 weight_mem_instance (
        .CLK(clk), .D(D_xmem), .Q(wmem_out),
        .CEN(wmem_CEN), .WEN(wmem_WEN), .A(wmem_add));

sram_128b_w2048 psum_mem_instance (
        .CLK(clk), .D(pmem_in), .Q(pmem_out),
        .CEN(pmem_CEN), .WEN(pmem_WEN), .A(pmem_add));

corelet #(.bw(bw), .psum_bw(bw_psum), .col(col), .row(row)) corelet_instance (
        .clk(clk),
        .reset(reset),
        .inst(inst[34:0]),
        .l0_in(xmem_out),
        .w_in(wmem_out),
        .out(corelet_out),
        .fifo_out(fifo_out),
        .ofifo_valid(ofifo_valid));

endmodule
