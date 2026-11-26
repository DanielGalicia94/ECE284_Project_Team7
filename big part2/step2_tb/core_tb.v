// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
`timescale 1ns/1ps

// ---------------- Part2 (differential input) additions ----------------
// The testbench plays the host/DRAM: it reads the raw frames X0..X3.txt (2048 8-bit integers each,
// layout (C,H,W) = (8,16,16): channel ic of group t is X[ic*256 + t]) and computes on the host side
//   X0_hi = X0 >> 4, X0_lo = X0 & 15, dXi = Xi - X0 (checked to fit signed 4 bits [-8,7]).
// Weights are loaded into the PEs ONCE (no reset afterwards). 5 passes (hi, lo, d1, d2, d3),
// each split into 4 tiles of 64 groups (L0 / OFIFO depth = 64).
// SFU: Y0 = (psum_hi << 4) + psum_lo -> pmem 1280+t ; Yi = Y0 + psum_di -> written back over psum_di.
// Compared with golden_y0..3.txt (gen_part2_diff.py).
// inst[34] = act_signed (1: signed 4b activations), inst[35] = shiftl (SFU input << 4)
// FRAME_UNSIGNED = 1: course frames v2 (0..255), act_signed per pass = 0,0,1,1,1
// FRAME_UNSIGNED = 0: course frames v1 (-128..127), act_signed per pass = 1,0,1,1,1
// Files: X0.txt X1.txt X2.txt X3.txt weight.txt golden_y0.txt golden_y1.txt golden_y2.txt golden_y3.txt

module core_tb;

parameter bw = 4;
parameter psum_bw = 16;
parameter len_kij = 9;
parameter len_onij = 16;
parameter col = 8;
parameter row = 8;
parameter len_nij = 36;
//parameters for psum write back. 512: Accumulation   1024: ReLU
parameter ACC_BASE  = 512;
parameter RELU_BASE = 1024;
//parameters for Part2
parameter FRAME_UNSIGNED = 1;
parameter NPIX  = 256;           // groups of 8 channels per frame (2048 / 8)
parameter TILE  = 64;            // groups per tile (= L0 / OFIFO depth)
parameter NTILE = NPIX / TILE;
parameter NPASS = 5;             // 0: X0_hi  1: X0_lo  2: dX1  3: dX2  4: dX3
parameter XMEM_W_BASE  = 1536;   // activations of pass p at p*256, weights here
parameter PMEM_Y0_BASE = 1280;   // psum of pass p at p*256, Y0 here

reg clk = 0;
reg reset = 1;

wire [35:0] inst_q; 

reg [1:0]  inst_w_q = 0; 
reg [bw*row-1:0] D_xmem_q = 0;
reg CEN_xmem = 1;
reg WEN_xmem = 1;
reg [10:0] A_xmem = 0;
reg CEN_xmem_q = 1;
reg WEN_xmem_q = 1;
reg [10:0] A_xmem_q = 0;
reg CEN_pmem = 1;
reg WEN_pmem = 1;
reg [10:0] A_pmem = 0;
reg CEN_pmem_q = 1;
reg WEN_pmem_q = 1;
reg [10:0] A_pmem_q = 0;
reg ofifo_rd_q = 0;
reg relu_q = 0;
reg first_acc_q = 0;
reg l0_rd_q = 0;
reg l0_wr_q = 0;
reg execute_q = 0;
reg load_q = 0;
reg acc_q = 0;
reg acc = 0;
reg act_signed_q = 0;
reg shiftl_q = 0;

reg [1:0]  inst_w; 
reg [bw*row-1:0] D_xmem;
reg [psum_bw*col-1:0] answer;


reg ofifo_rd;
reg relu;
reg first_acc;
reg l0_rd;
reg l0_wr;
reg execute;
reg load;
reg act_signed;
reg shiftl;
reg [8*30:1] stringvar;
reg [8*30:1] w_file_name;
wire ofifo_valid;
wire [col*psum_bw-1:0] sfp_out;

integer x_file, x_scan_file ; // file_handler
integer w_file, w_scan_file ; // file_handler
integer acc_file, acc_scan_file ; // file_handler
integer out_file, out_scan_file ; // file_handler
integer captured_data; 
integer t, i, j, k, kij;
integer error;
integer X0 [0:2047];
integer X1 [0:2047];
integer X2 [0:2047];
integer X3 [0:2047];
integer fd, r, val;
integer p, tile, pix, fi;
integer nerr_pass, delta_err;
integer cycle = 0;
integer exec_cycles = 0;
integer passes_run = 0;
integer array_start, array_cycles, sfu_start, sfu_cycles;

assign inst_q[33] = acc_q;
assign inst_q[32] = CEN_pmem_q;
assign inst_q[31] = WEN_pmem_q;
assign inst_q[30:20] = A_pmem_q;
assign inst_q[19]   = CEN_xmem_q;
assign inst_q[18]   = WEN_xmem_q;
assign inst_q[17:7] = A_xmem_q;
assign inst_q[6]   = ofifo_rd_q;
assign inst_q[5]   = relu_q; //borrow for relu
assign inst_q[4]   = first_acc_q; //borrow for first accumulation
assign inst_q[3]   = l0_rd_q;
assign inst_q[2]   = l0_wr_q;
assign inst_q[1]   = execute_q; 
assign inst_q[0]   = load_q; 
assign inst_q[34]  = act_signed_q;
assign inst_q[35]  = shiftl_q;


core  #(.bw(bw), .col(col), .row(row)) core_instance (
	.clk(clk), 
	.inst(inst_q),
	.ofifo_valid(ofifo_valid),
    .D_xmem(D_xmem_q), 
    .sfp_out(sfp_out), 
	.reset(reset)); 


// read one frame file (2048 integers, one per line)
task read_frame;
  input integer which;
  input [8*16:1] fname;
  integer n;
begin
  fd = $fopen(fname, "r");
  if (fd == 0) begin $display("ERROR: cannot open %0s", fname); $finish; end
  for (n=0; n<2048; n=n+1) begin
    r = $fscanf(fd, "%d", val);
    case (which)
      0: X0[n] = val;
      1: X1[n] = val;
      2: X2[n] = val;
      3: X3[n] = val;
    endcase
  end
  $fclose(fd);
end
endtask

// host side: 32-bit xmem word of pass p_ for group pix_ (ch7 at MSB)
function [bw*row-1:0] pack_word;
  input integer p_;
  input integer pix_;
  integer c, a, d;
begin
  pack_word = 0;
  for (c=0; c<col; c=c+1) begin
    a = X0[c*NPIX + pix_];
    case (p_)
      0: d = a >>> 4;                    // X0_hi
      1: d = a & 15;                     // X0_lo (unsigned)
      2: d = X1[c*NPIX + pix_] - a;      // dX1
      3: d = X2[c*NPIX + pix_] - a;      // dX2
      default: d = X3[c*NPIX + pix_] - a;// dX3
    endcase
    pack_word[bw*c +: bw] = d[3:0];
  end
end
endfunction


initial begin 

  inst_w   = 0; 
  D_xmem   = 0;
  CEN_xmem = 1;
  WEN_xmem = 1;
  A_xmem   = 0;
  ofifo_rd = 0;
  relu = 0;
  first_acc = 0;
  l0_rd    = 0;
  l0_wr    = 0;
  execute  = 0;
  load     = 0;
  act_signed = 0;
  shiftl = 0;

  $dumpfile("core_tb.vcd");
  $dumpvars(0,core_tb);

  //////// Host: read frames and check deltas ////////
  read_frame(0, "X0.txt");
  read_frame(1, "X1.txt");
  read_frame(2, "X2.txt");
  read_frame(3, "X3.txt");
  error = 0;
  delta_err = 0;
  for (i=0; i<2048; i=i+1) begin
    if ( FRAME_UNSIGNED && (X0[i] < 0    || X0[i] > 255)) delta_err = delta_err + 1;
    if (!FRAME_UNSIGNED && (X0[i] < -128 || X0[i] > 127)) delta_err = delta_err + 1;
    if (X1[i]-X0[i] < -8 || X1[i]-X0[i] > 7) delta_err = delta_err + 1;
    if (X2[i]-X0[i] < -8 || X2[i]-X0[i] > 7) delta_err = delta_err + 1;
    if (X3[i]-X0[i] < -8 || X3[i]-X0[i] > 7) delta_err = delta_err + 1;
  end
  if (delta_err != 0) begin
    $display("ERROR: %0d values do not fit (X0 8b, dX 4b signed [-8,7])", delta_err);
    error = 1;
  end
  else $display("Host: all dX fit in signed 4 bits");
  /////////////////////////////////////////////////

  //////// Reset /////////
  #0.5 clk = 1'b0;   reset = 1;
  #0.5 clk = 1'b1; 

  for (i=0; i<10 ; i=i+1) begin
    #0.5 clk = 1'b0;
    #0.5 clk = 1'b1;  
  end

  #0.5 clk = 1'b0;   reset = 0;
  #0.5 clk = 1'b1; 

  #0.5 clk = 1'b0;   
  #0.5 clk = 1'b1;   
  /////////////////////////

  /////// Activation data writing to memory (5 passes x 256 groups) ///////
  for (p=0; p<NPASS; p=p+1) begin
    for (t=0; t<NPIX; t=t+1) begin
      #0.5 clk = 1'b0;  D_xmem = pack_word(p, t); WEN_xmem = 0; CEN_xmem = 0; A_xmem = p*NPIX + t;
      #0.5 clk = 1'b1;
    end
  end

  #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
  #0.5 clk = 1'b1;
  /////////////////////////////////////////////////


  /////// Kernel data writing to memory ///////
  w_file = $fopen("weight.txt", "r");
  if (w_file == 0) begin $display("ERROR: cannot open weight.txt"); $finish; end
  // Following three lines are to remove the first three comment lines of the file
  w_scan_file = $fscanf(w_file,"%s", captured_data);
  w_scan_file = $fscanf(w_file,"%s", captured_data);
  w_scan_file = $fscanf(w_file,"%s", captured_data);

  A_xmem = XMEM_W_BASE;

  for (t=0; t<col; t=t+1) begin
    #0.5 clk = 1'b0;  w_scan_file = $fscanf(w_file,"%32b", D_xmem); WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1;
    #0.5 clk = 1'b1;
  end

  #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
  #0.5 clk = 1'b1;
  $fclose(w_file);
  /////////////////////////////////////


  /////// Kernel data writing to L0 ///////
  A_xmem = XMEM_W_BASE;

  for (t=0; t<col+1; t=t+1) begin
      #0.5 clk = 1'b0;
      if (t<col) begin CEN_xmem = 0; WEN_xmem = 1; if (t>0) A_xmem = A_xmem + 1; end
      else       begin CEN_xmem = 1; end
      if (t>0)   begin l0_wr = 1'b1; end
      #0.5 clk = 1'b1;
  end
  #0.5 clk = 1'b0; l0_wr = 0; CEN_xmem = 1; A_xmem = 0;
  #0.5 clk = 1'b1;
  /////////////////////////////////////


  /////// Kernel loading to PEs (only once, no reset afterwards) ///////
  for (t=0; t<col; t=t+1) begin
      #0.5 clk = 1'b0; l0_rd = 1; load = 1;
      #0.5 clk = 1'b1;
  end
  /////////////////////////////////////


  ////// provide some intermission to clear up the kernel loading ///
  #0.5 clk = 1'b0;  load = 0; l0_rd = 0;
  #0.5 clk = 1'b1;

  for (i=0; i<10 ; i=i+1) begin
    #0.5 clk = 1'b0;
    #0.5 clk = 1'b1;
  end
  /////////////////////////////////////


  array_start = cycle;
  for (p=0; p<NPASS; p=p+1) begin  // pass loop: X0_hi, X0_lo, dX1, dX2, dX3

    // X0_lo is always unsigned, X0_hi is unsigned for unsigned frames, dX is signed
    #0.5 clk = 1'b0; act_signed = (p == 1 || (p == 0 && FRAME_UNSIGNED)) ? 0 : 1;
    #0.5 clk = 1'b1;

    for (tile=0; tile<NTILE; tile=tile+1) begin  // tile loop: 4 x 64 groups

      /////// Activation data writing to L0 ///////
      A_xmem = p*NPIX + tile*TILE;

      for (t=0; t<TILE+1; t=t+1) begin
          #0.5 clk = 1'b0;
          if (t<TILE) begin CEN_xmem = 0; WEN_xmem = 1; if (t>0) A_xmem = A_xmem + 1; end
          else        begin CEN_xmem = 1; end
          if (t>0)    begin l0_wr = 1'b1; end
          #0.5 clk = 1'b1;
      end
      #0.5 clk = 1'b0; l0_wr = 0; CEN_xmem = 1; A_xmem = 0;
      #0.5 clk = 1'b1;
      /////////////////////////////////////


      /////// Execution ///////
      for (t=0; t<TILE; t=t+1) begin
          #0.5 clk = 1'b0; l0_rd = 1; execute = 1;
          #0.5 clk = 1'b1;
      end

          #0.5 clk = 1'b0; l0_rd = 0; execute = 0;
          #0.5 clk = 1'b1;

      for (i=0; i<row+col+2; i=i+1) begin
        #0.5 clk = 1'b0;
        #0.5 clk = 1'b1;
      end
      /////////////////////////////////////


      //////// OFIFO READ ////////
      for (t=0; t<TILE; t=t+1) begin
          #0.5 clk = 1'b0; ofifo_rd = 1; CEN_pmem = 0; WEN_pmem = 0; A_pmem = p*NPIX + tile*TILE + t;
          #0.5 clk = 1'b1;
      end
      #0.5 clk = 1'b0; ofifo_rd = 0; CEN_pmem = 1; WEN_pmem = 1; A_pmem = 0;
      #0.5 clk = 1'b1;
      /////////////////////////////////////

    end  // end of tile loop
    passes_run = passes_run + 1;

  end  // end of pass loop
  #0.5 clk = 1'b0; act_signed = 0;
  #0.5 clk = 1'b1;
  array_cycles = cycle - array_start;


  ////////// SFU: Y0 and Yi /////////
  sfu_start = cycle;
  $display("############ Verification Start #############");

  for (fi=0; fi<4; fi=fi+1) begin  // fi = 0: Y0, 1..3: Y1..Y3
    case (fi)
      0: out_file = $fopen("golden_y0.txt", "r");
      1: out_file = $fopen("golden_y1.txt", "r");
      2: out_file = $fopen("golden_y2.txt", "r");
      3: out_file = $fopen("golden_y3.txt", "r");
    endcase
    if (out_file == 0) begin $display("ERROR: cannot open golden_y%0d.txt", fi); $finish; end
    // Following three lines are to remove the first three comment lines of the file
    out_scan_file = $fscanf(out_file,"%s", answer);
    out_scan_file = $fscanf(out_file,"%s", answer);
    out_scan_file = $fscanf(out_file,"%s", answer);
    nerr_pass = 0;

    for (pix=0; pix<NPIX; pix=pix+1) begin
      // read 1st operand: psum of X0_hi (Y0) or stored Y0 (Yi)
      #0.5 clk = 1'b0; CEN_pmem = 0; WEN_pmem = 1;
      A_pmem = (fi == 0) ? 0*NPIX + pix : PMEM_Y0_BASE + pix;
      #0.5 clk = 1'b1;
      // read 2nd operand: psum of X0_lo (Y0) or psum of dXi (Yi); first_acc on 1st operand
      #0.5 clk = 1'b0;
      A_pmem = (fi == 0) ? 1*NPIX + pix : (fi+1)*NPIX + pix;
      acc = 1; first_acc = 1; shiftl = (fi == 0);
      #0.5 clk = 1'b1;
      // accumulate 2nd operand
      #0.5 clk = 1'b0; CEN_pmem = 1; acc = 1; first_acc = 0; shiftl = 0;
      #0.5 clk = 1'b1;
      // write back to psum
      #0.5 clk = 1'b0; acc = 0; CEN_pmem = 0; WEN_pmem = 0;
      A_pmem = (fi == 0) ? PMEM_Y0_BASE + pix : (fi+1)*NPIX + pix;
      #0.5 clk = 1'b1;

      #0.5 clk = 1'b0; CEN_pmem = 1; WEN_pmem = 1; A_pmem = 0;
      #0.5 clk = 1'b1;

      out_scan_file = $fscanf(out_file,"%128b", answer); // reading from golden file to answer
      if (sfp_out !== answer) begin
        if (nerr_pass < 5) begin
          $display("Y%0d %3d-th output Data ERROR!!", fi, pix);
          $display("sfpout: %128b", sfp_out);
          $display("answer: %128b", answer);
        end
        nerr_pass = nerr_pass + 1;
        error = 1;
      end
    end
    $fclose(out_file);
    if (nerr_pass == 0) $display("Y%0d: all %0d outputs matched! :D", fi, NPIX);
    else                $display("Y%0d: %0d / %0d outputs ERROR!!", fi, nerr_pass, NPIX);
  end
  sfu_cycles = cycle - sfu_start;

  $display("---------------- pass / cycle report ----------------");
  $display("array passes run (differential): %0d   (conventional would need 8)", passes_run);
  $display("execute cycles: %0d   array-phase cycles: %0d   (%0d per pass)",
           exec_cycles, array_cycles, array_cycles / passes_run);
  $display("conventional estimate: %0d array-phase cycles (8 passes)", (array_cycles / passes_run) * 8);
  $display("SFU-phase cycles: %0d", sfu_cycles);

  if (error == 0) begin
  	$display("############ No error detected ##############"); 
  	$display("########### Project Completed !! ############"); 
  end
  //////////////////////////////////

  for (t=0; t<10; t=t+1) begin  
    #0.5 clk = 1'b0;  
    #0.5 clk = 1'b1;  
  end

  #10 $finish;

end

always @ (posedge clk) begin
   inst_w_q   <= inst_w; 
   D_xmem_q   <= D_xmem;
   CEN_xmem_q <= CEN_xmem;
   WEN_xmem_q <= WEN_xmem;
   A_pmem_q   <= A_pmem;
   CEN_pmem_q <= CEN_pmem;
   WEN_pmem_q <= WEN_pmem;
   A_xmem_q   <= A_xmem;
   ofifo_rd_q <= ofifo_rd;
   acc_q      <= acc;
   relu_q <= relu;
   first_acc_q <= first_acc;
   l0_rd_q    <= l0_rd;
   l0_wr_q    <= l0_wr ;
   execute_q  <= execute;
   load_q     <= load;
   act_signed_q <= act_signed;
   shiftl_q   <= shiftl;
   cycle = cycle + 1;
   if (execute_q) exec_cycles = exec_cycles + 1;
end


endmodule




