`timescale 1ns / 1ps
/*
multi_corelet: NI x NO identical corelets driven in lock-step by one shared instruction.
The SRAMs are in multi_core.v.
Core (ci, co) has index c = ci*NO + co and uses bus slice [c*W +: W].
1. Cores side by side (same ci) get the same activations and different output-channel tiles.
2. Cores stacked (same co) get different input-channel tiles, so their partial sums are added:
   when inst[34] is set, the SFP of core (0,co) takes the SFP output of core (1,co) as input.
3. inst[33:0] has the same encoding as corelet.v. Only NI = 1 or 2 is supported.
*/
module multi_corelet (clk, reset, inst, l0_in, sfp_in, out, ofifo_valid, fifo_out);

parameter NI      = 2;          // cores along input-channel tiles  (1 or 2)
parameter NO      = 2;          // cores along output-channel tiles (any >= 1)
parameter col     = 8;
parameter row     = 8;
parameter bw      = 4;
parameter bw_psum = 2*bw+8;
localparam NC     = NI*NO;
localparam XW     = row*bw;        // activation/weight word per core
localparam PW     = col*bw_psum;   // psum word per core

input                clk;
input                reset;
input  [34:0]        inst;
input  [NC*XW-1:0]   l0_in;
input  [NC*PW-1:0]   sfp_in;       // from each core's psum SRAM
output [NC*PW-1:0]   out;          // each core's SFP output
output [NC*PW-1:0]   fifo_out;     // each core's OFIFO output
output               ofifo_valid;  // all OFIFOs valid

wire        red = inst[34];
wire [NC-1:0] valid_c;

assign ofifo_valid = &valid_c;

genvar ci, co;
generate
  for (ci = 0; ci < NI; ci = ci + 1) begin : g_ci
    for (co = 0; co < NO; co = co + 1) begin : g_co
      localparam c = ci*NO + co;
      wire [PW-1:0] sfp_in_c;

      if (ci + 1 < NI) begin : g_red
        // partial sum of the core below, added in the reduction cycle
        assign sfp_in_c = red ? out[(c+NO)*PW +: PW] : sfp_in[c*PW +: PW];
      end else begin : g_last
        assign sfp_in_c = red ? {PW{1'b0}} : sfp_in[c*PW +: PW];
      end

      corelet #(.bw(bw), .bw_psum(bw_psum), .col(col), .row(row)) corelet_inst (
        .clk        (clk),
        .reset      (reset),
        .inst       (inst[33:0]),
        .l0_in      (l0_in[c*XW +: XW]),
        .sfp_in     (sfp_in_c),
        .out        (out[c*PW +: PW]),
        .ofifo_valid(valid_c[c]),
        .fifo_out   (fifo_out[c*PW +: PW])
      );
    end
  end
endgenerate

endmodule
