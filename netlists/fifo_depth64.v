// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission
module fifo_depth64 (rd_clk, wr_clk, in, out, rd, wr, o_full, o_empty, reset);

  parameter bw = 4;
  parameter simd = 1;

  input  rd_clk;
  input  wr_clk;
  input  rd;
  input  wr;
  input  reset;
  output o_full;
  output o_empty;
  input  [simd*bw-1:0] in;
  output [simd*bw-1:0] out;

  wire full, empty;

  reg [6:0] rd_ptr;
  reg [6:0] wr_ptr;

  // reg [simd*bw-1:0] q0;
  // reg [simd*bw-1:0] q1;
  // reg [simd*bw-1:0] q2;
  // reg [simd*bw-1:0] q3;
  // reg [simd*bw-1:0] q4;
  // reg [simd*bw-1:0] q5;
  // reg [simd*bw-1:0] q6;
  // reg [simd*bw-1:0] q7;
  // reg [simd*bw-1:0] q8;
  // reg [simd*bw-1:0] q9;
  // reg [simd*bw-1:0] q10;
  // reg [simd*bw-1:0] q11;
  // reg [simd*bw-1:0] q12;
  // reg [simd*bw-1:0] q13;
  // reg [simd*bw-1:0] q14;
  // reg [simd*bw-1:0] q15;
  reg [simd*bw-1:0] q [0:63];


 assign empty = (wr_ptr == rd_ptr) ? 1'b1 : 1'b0 ;
 assign full  = ((wr_ptr[5:0] == rd_ptr[5:0]) && (wr_ptr[6] != rd_ptr[6])) ? 1'b1 : 1'b0;

 assign o_full  = full;
 assign o_empty = empty;
 
assign out = q[rd_ptr[5:0]];

 always @ (posedge rd_clk or posedge reset) begin
    if (reset) begin
       rd_ptr <= 7'b0000000;
    end
    else if ((rd == 1) && (empty == 0)) begin
       rd_ptr <= rd_ptr + 1;
    end
 end


 always @ (posedge wr_clk or posedge reset) begin
    if (reset) begin
       wr_ptr <= 7'b0000000;
    end
    else begin
        if ((wr == 1) && (full == 0)) begin
            wr_ptr <= wr_ptr + 1;
        end

        if ((wr == 1) && (full == 0)) begin
        // case (wr_ptr[3:0])
        //  4'b0000   :    q0  <= in ;
        //  4'b0001   :    q1  <= in ;
        //  4'b0010   :    q2  <= in ;
        //  4'b0011   :    q3  <= in ;
        //  4'b0100   :    q4  <= in ;
        //  4'b0101   :    q5  <= in ;
        //  4'b0110   :    q6  <= in ;
        //  4'b0111   :    q7  <= in ;
        //  4'b1000   :    q8  <= in ;
        //  4'b1001   :    q9  <= in ;
        //  4'b1010   :    q10 <= in ;
        //  4'b1011   :    q11 <= in ;
        //  4'b1100   :    q12 <= in ;
        //  4'b1101   :    q13 <= in ;
        //  4'b1110   :    q14 <= in ;
        //  4'b1111   :    q15 <= in ;
        // endcase
            q[wr_ptr[5:0]] <= in;
        end
    end
 end
endmodule
