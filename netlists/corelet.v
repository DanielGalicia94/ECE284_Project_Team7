`timescale 1ns / 1ps

module corelet(clk, reset, inst, l0_in, sfp_in, out, ofifo_valid, fifo_out);

parameter col = 8;
parameter row = 8;
parameter bw = 4;
parameter bw_psum = 2*bw+8;

input  clk;
input  reset;
input  [33:0] inst; 
input  [row*bw-1:0] l0_in;
input  [bw_psum*col-1:0] sfp_in;
output ofifo_valid;
output [bw_psum*col-1:0] out;
output [bw_psum*col-1:0] fifo_out; 

wire  [row*bw-1:0] l0_out;
wire  [bw_psum*col-1:0] fifo_out;
wire  [bw_psum*col-1:0] sfp_out;
wire  [bw_psum*col-1:0] array_out;

wire  l0_rd;
wire  l0_wr;
wire  l0_valid;
wire  [col-1:0] fifo_wr;
wire  fifo_rd;
wire  fifo_valid;
wire  acc;
wire  relu;
//wire  sfp_wr;
//reg  [3:0] sfp_wr_add;

//value assign
assign out = sfp_out;
assign ofifo_valid = fifo_valid;
//inst assignment
assign acc = inst[33];
assign fifo_rd = inst[6];
assign relu = inst[5]; //since we are not using ififo, I borrow its control signal for sfp
assign l0_rd = inst[3];
assign l0_wr = inst[2];



l0 #(.bw(bw), .row(row)) l0_inst (
        .clk(clk),
        .in(l0_in),
        .out(l0_out),
        .rd(l0_rd),
        .wr(l0_wr),
        .o_full(),
        .reset(reset),
        .o_ready(l0_valid)
);

mac_array #(.bw(bw), .psum_bw(bw_psum), .col(col), .row(row)) mac_array_instance (
        .clk(clk), 
        .reset(reset), 
        .out_s(array_out),
        .in_w(l0_out),
        .in_n({(col*bw_psum){1'b0}}),
        .inst_w(inst[1:0]),     
        .valid(fifo_wr)
);

ofifo #(.bw(bw_psum), .col(col)) ofifo_inst (
        .clk(clk),
        .reset(reset),
        .in(array_out),
        .wr(fifo_wr),
        .rd(fifo_rd),
        .o_valid(fifo_valid),
        .out(fifo_out)
);

sfp #(.col(col), .psum_bw(bw_psum))sfp_inst (
        .clk(clk),
        .reset(reset),
        .in(sfp_in),
        .out(sfp_out),
        .acc(acc),
        .relu(relu)
);

endmodule
