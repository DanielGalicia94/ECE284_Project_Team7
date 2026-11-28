// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module mac_tile (clk, out_s, in_w, out_e, in_n, inst_w, inst_e, reset, drain);

parameter bw = 4;
parameter psum_bw = 16;

output [psum_bw-1:0] out_s;
input  [bw-1:0] in_w;
output [bw-1:0] out_e; 
input  [1:0] inst_w;   // inst[1]:execute, inst[0]: kernel loading
output [1:0] inst_e;
input  [psum_bw-1:0] in_n;
input  clk;
input  reset;
input drain; //drain=1=> sending psum_q down. drain=0 => sending the

reg [bw-1:0] a_q;
reg [bw-1:0] b_q;
reg [psum_bw-1:0] c_q; //stores incoming partial sum
 //Before in WS: Controls whether a weight can be loaded. Now in OS: Controls whether an output/psum can be loaded
reg [1:0] inst_q;  //Stores the instruction for next PE

wire [psum_bw-1:0] mac_out;

assign out_s = drain ? c_q : {{(psum_bw-bw){b_q[bw-1]}}, b_q};   //Before in WS: Sends MAC result (partial sum) to the PE below. Now in OS: Sends the weights below
assign out_e = a_q;  //Sends activations to the PE on the right
assign inst_e = inst_q;   //Sends instruction to the PE on the right

always @(posedge clk) begin
        if (reset) begin
                a_q <= 0;     //When reset is active, all the data registers become zero. 
                b_q <= 0;
                c_q <=0;
                inst_q <= 0;       // all the instructions are cleared
        end 
        else begin
                if (drain==0) begin  //drain=0 => normal execution of OS.
                        a_q<=in_w;
                        b_q<=in_n[bw-1:0];
                        if (inst_q[1]) c_q<=mac_out;
                        inst_q<=inst_w;
                end
                else begin
                        //If drain==1, computation is finished. We need to get the results out.
                        //a_q no longer needed for MAC computation.
                        //b_q no longer needed for MAC computation.
                        //c_q receives partial sum from in_n;
                        //out_s sends partial sum c_q downwards. 
                        c_q<=in_n;

                end
        end

               

end

mac #(.bw(bw), .psum_bw(psum_bw)) mac_instance (
        .a(a_q), 
        .b(b_q),
        .c(c_q),
	.out(mac_out)
); 

endmodule
