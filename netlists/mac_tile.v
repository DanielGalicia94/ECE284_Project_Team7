// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module mac_tile (clk, out_s, in_w, out_e, in_n, inst_w, inst_e, reset);

parameter bw = 4;
parameter psum_bw = 16;

output [psum_bw-1:0] out_s;
input  [bw-1:0] in_w; // inst[1]:execute, inst[0]: kernel loading
output [bw-1:0] out_e; 
input  [1:0] inst_w;
output [1:0] inst_e;
input  [psum_bw-1:0] in_n;
input  clk;
input  reset;

reg [bw-1:0] a_q;
reg [bw-1:0] b_q;
reg [psum_bw-1:0] c_q;
reg load_ready_q;
reg [1:0] inst_q;
reg [bw-1:0]      a_mul;     // multiplier's own activation input
reg [psum_bw-1:0] c_mul;     // adder's own psum input
reg               w_zero_q;  // guard bit
reg               zero_q;

wire [psum_bw-1:0] mac_out;

assign out_s = zero_q ? c_q : mac_out;
assign out_e = a_q;
assign inst_e = inst_q;

always @(posedge clk) begin
        if (reset) begin
                a_q <= 0;
                b_q <= 0;
                c_q <=0;
                load_ready_q <= 1;
                inst_q <= 0;
                a_mul    <= 0;
                c_mul    <= 0;
                w_zero_q <= 1'b1;   // b_q resets to 0, so the flag starts at 1
                zero_q   <= 1'b0;
        end else begin
                inst_q[1] <= inst_w[1];

                if (~load_ready_q) begin
                        inst_q[0] <= inst_w[0];
                end

                if (inst_w[0] && load_ready_q) begin
                        b_q <= in_w;
                        load_ready_q <= 1'b0;
                        w_zero_q <= (in_w == 0);
                end

                if (inst_w[0] || inst_w[1]) begin 
                        a_q <= in_w;
                end

                c_q <= in_n;
                if (inst_w[1]) begin
                        zero_q <= (in_w == 0) | w_zero_q;
                        if ((in_w != 0) & ~w_zero_q) begin
                                a_mul <= in_w;
                                c_mul <= in_n;
                        end
                end
        end
end

mac #(.bw(bw), .psum_bw(psum_bw)) mac_instance (
        .a(a_mul), 
        .b(b_q),
        .c(c_mul),
	.out(mac_out)
); 

endmodule
