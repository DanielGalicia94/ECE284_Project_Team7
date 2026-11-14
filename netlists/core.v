// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission
module core (clk, D_xmem, sfp_out, inst, reset, ofifo_valid);

parameter col = 8;
parameter row = 8;
parameter bw = 4;
parameter bw_psum = 2*bw+8;

input  [row*bw-1:0] D_xmem;
input  clk;
input  [33:0] inst; 
input  reset;
output [bw_psum*col-1:0] sfp_out;
output ofifo_valid;

wire  [row*bw-1:0] xmem_out;
wire  [bw_psum*col-1:0] pmem_in;
wire  [bw_psum*col-1:0] pmem_out;
wire  [bw_psum*col-1:0] corelet_out;
wire  [bw_psum*col-1:0] fifo_out;
wire  [bw_psum*col-1:0] sfp_in;

wire  [10:0] xmem_add;
wire  [10:0] pmem_add;

wire  xmem_CEN;
wire  xmem_WEN;
wire  pmem_CEN;
wire  pmem_WEN;

//value assign
assign sfp_in = pmem_out;
assign sfp_out = corelet_out;
assign pmem_in = inst[6] ? fifo_out : corelet_out;

//inst assign
assign xmem_CEN = inst[19];
assign xmem_WEN = inst[18];
assign xmem_add = inst[17:7];
assign pmem_CEN = inst[32];
assign pmem_WEN = inst[31];
assign pmem_add = inst[30:20];



sram_32b_w2048 acivation_weight_mem_instance (
        .CLK(clk),
        .D(D_xmem),
        .Q(xmem_out),
        .CEN(xmem_CEN),
        .WEN(xmem_WEN), 
        .A(xmem_add)
);

sram_128b_w2048 psum_mem_instance (
        .CLK(clk),
        .D(pmem_in),
        .Q(pmem_out),
        .CEN(pmem_CEN),
        .WEN(pmem_WEN), 
        .A(pmem_add)
);

corelet #(.bw(bw), .bw_psum(bw_psum), .col(col), .row(row)) corelet_instance (
        .clk(clk), 
        .reset(reset),
        .inst(inst),
        .l0_in(xmem_out), 
        .sfp_in(sfp_in),
        .ofifo_valid(ofifo_valid),
        .out(corelet_out),
        .fifo_out(fifo_out)
);

//always @(posedge clk) begin
//        if (reset) begin
//		sfp_wr_add <= 0;
//        end 
//        else begin
//		if(sfp_wr) sfp_wr_add <= sfp_wr_add+1;
//        end
//end

//   //////////// For printing purpose ////////////
//   always @(posedge clk) begin
//       if(pmem_wr)
//          $display("Memory write to PSUM mem add %x %x ", pmem_add, pmem_in); 
//   end
//assign sum_out = pmem_out[bw_psum+3:0];



endmodule
