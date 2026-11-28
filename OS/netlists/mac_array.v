// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module mac_array (clk, reset, out_s, in_w, in_n, inst_w, valid, drain);

  parameter bw = 4;
  parameter psum_bw = 16;
  parameter col = 8;
  parameter row = 8;

  input  clk, reset;
  output [psum_bw*col-1:0] out_s;
  input  [row*bw-1:0] in_w; // inst[1]:execute, inst[0]: kernel loading
  input  [1:0] inst_w;
  input  [bw*col-1:0] in_n;
  output [col-1:0] valid;
  input drain;



  reg    [2*row-1:0] inst_w_temp; 
  wire   [psum_bw*col*(row+1)-1:0] temp;
  wire   [row*col-1:0] valid_temp;


  genvar i;
 
  assign out_s = temp[psum_bw*col*9-1:psum_bw*col*8];
  
  genvar j;
    for (j=1; j < col+1 ; j=j+1) begin : top_col
        assign temp[psum_bw*j-1 : psum_bw*(j-1)] =
            drain ? {psum_bw{1'b0}}
                : {{(psum_bw-bw){in_n[bw*j-1]}}, in_n[bw*j-1 : bw*(j-1)]};
    end
  
  assign valid = valid_temp[row*col-1:row*col-8];

  for (i=1; i < row+1 ; i=i+1) begin : row_num
      mac_row #(.bw(bw), .psum_bw(psum_bw)) mac_row_instance (
         .clk(clk),
         .reset(reset),
	 .in_w(in_w[bw*i-1:bw*(i-1)]),
	 .inst_w(inst_w_temp[2*i-1:2*(i-1)]),
	 .in_n(temp[psum_bw*col*i-1:psum_bw*col*(i-1)]),
         .valid(valid_temp[col*i-1:col*(i-1)]),
	 .out_s(temp[psum_bw*col*(i+1)-1:psum_bw*col*(i)]), .drain(drain));
  end

  always @ (posedge clk) begin
    if (reset) 
        inst_w_temp<=0;
    else begin

    //valid <= valid_temp[row*col-1:row*col-8];
        inst_w_temp[1:0]   <= inst_w; 
        inst_w_temp[3:2]   <= inst_w_temp[1:0]; 
        inst_w_temp[5:4]   <= inst_w_temp[3:2]; 
        inst_w_temp[7:6]   <= inst_w_temp[5:4]; 
        inst_w_temp[9:8]   <= inst_w_temp[7:6]; 
        inst_w_temp[11:10] <= inst_w_temp[9:8]; 
        inst_w_temp[13:12] <= inst_w_temp[11:10]; 
        inst_w_temp[15:14] <= inst_w_temp[13:12]; 
    end
  end



endmodule