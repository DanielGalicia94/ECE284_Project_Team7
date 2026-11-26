`timescale 1ns / 1ps

module sfp(clk, reset, acc, first_acc, in, relu, shiftl, out);

parameter col = 8;
parameter bw = 4;
parameter psum_bw = 2*bw+8;

input  clk;
input  reset;
input  acc;
input  relu;
input  first_acc;
input  shiftl;
input  [psum_bw*col-1:0] in;
output [psum_bw*col-1:0] out;

genvar i;
generate
for (i = 0; i < col; i = i + 1) begin : col_num
    reg signed [psum_bw-1:0] acc_q;
    wire signed [psum_bw-1:0] in_i = in[psum_bw*(i+1)-1 : psum_bw*i];
    wire signed [psum_bw-1:0] in_s = shiftl ? (in_i <<< 4) : in_i;

    always @(posedge clk) begin
        if (reset)     acc_q <= 0;
        else if (acc)  acc_q <= first_acc ? in_s : acc_q + in_s;
        else if (relu) acc_q <= acc_q[psum_bw-1] ? 0 : acc_q;        
    end

    assign out[psum_bw*(i+1)-1 : psum_bw*i] = acc_q;             
end
endgenerate
endmodule
