// sfu.v : Special Function Unit
//Note: In WS each output needed 9 partial psums (one per kij) added together, so the SFU had an accumulator. It read the psum words for each kij, added them, then applied ReLU, with many psum SRAM reads and writes.
//In OS each PE already added over all 9 kij and all 8 input channels, so the psum in SRAM is final. The SFU only needs ReLU: negative values become 0, and positive values pass through unchanged.
//// The SFU only applies ReLU, independently for each of the 8 output channels.


module sfp (clk, reset, in, out);

  parameter col = 8;
  parameter psum_bw = 16;

  input  clk;
  input  reset;
  //input  acc;                       // 1 = add this cycle's input (from inst[33])
  input  [psum_bw*col-1:0] in;      // 8 psums from pmem (column 0 in the lowest bits)
  output [psum_bw*col-1:0] out;     // 8 results after ReLU -> sfp_out

  genvar i;

  for (i=0; i<col; i=i+1) begin
    assign out[psum_bw*(i+1)-1:psum_bw*i] = in[psum_bw*(i+1)-1]?{psum_bw{1'b0}}:in[psum_bw*(i+1)-1:psum_bw*i];
  end


endmodule