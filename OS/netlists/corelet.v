module corelet(clk, reset, inst, l0_in, w_in, out, fifo_out, ofifo_valid);

parameter bw=4;
parameter psum_bw=16;
parameter row=8;
parameter col=8;

input clk;
input reset;
input [34:0]inst;
input [bw*row-1:0] l0_in;
input [bw*col-1:0] w_in;
output [psum_bw*col-1:0] out;
output [psum_bw*col-1:0] fifo_out;
output ofifo_valid;

wire [bw*row-1:0] l0_out;
wire [bw*col-1:0] ififo_out;
wire [psum_bw*col-1:0] array_out;
wire [col-1:0] fifo_wr;
wire [psum_bw*col-1:0] sfp_out;


//Note: Control bits in instruction ("inst"). {inst[34]: Drain, inst[6]: fifo_rd, inst[5]: ififo_wr, inst[4]: ififo_rd. inst[3]:l0_rd, inst[2]: l0_wr, inst[1]: execute}
l0 #(.bw(bw), .row(row)) l0_inst(.clk(clk), .in(l0_in), .out(l0_out), .rd(inst[3]), .wr(inst[2]), .reset(reset));

l0 #(.bw(bw), .row(col)) ififo_inst(.clk(clk), .in(w_in), .out(ififo_out), .rd(inst[4]), .wr(inst[5]), .reset(reset));

mac_array #(.bw(bw), .psum_bw(psum_bw), .row(row), .col(col)) mac_array_inst(.clk(clk), .reset(reset), .out_s(array_out), .in_w(l0_out), .in_n(ififo_out), .inst_w({inst[1], 1'b0}), .valid(fifo_wr), .drain(inst[34]));

ofifo #(.bw(psum_bw), .col(col)) ofifo_inst(.clk(clk), .reset(reset), .in(array_out), .out(fifo_out), .rd(inst[6]), .wr(fifo_wr), .o_valid(ofifo_valid));

sfp #(.col(col), .psum_bw(psum_bw)) sfp_inst(.clk(clk), .reset(reset), .in(fifo_out), .out(sfp_out));


assign out = sfp_out;

endmodule