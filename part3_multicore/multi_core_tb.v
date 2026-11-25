/*
Testbench for multi_core: a 3x3 conv with 8*IT input and 8*OT output channels on a 6x6 padded input.
Core c = ci*NO + co handles itile ci + NI*a and otile co + NO*b, all cores in lock-step.
For every (b, a, kij) it runs the same stages as core_tb.v. Then for every output pixel the SFP
accumulates the psums, adds the partial sum of the other core when NI = 2, applies ReLU, and the
pre- and post-ReLU results are compared with the golden files.
Run it from the vector directory (e.g. part4_multicore), see part3_multicore/README.md for the commands.
NI and NO are set with iverilog -P, the plusarg +NO_VCD skips the waveform dump.
*/
`timescale 1ns/1ps

module multi_core_tb;

parameter NI = 2;                 // cores along input-channel tiles (1 or 2)
parameter NO = 2;                 // cores along output-channel tiles
parameter IT = 2;                 // input-channel tiles of the layer
parameter OT = 2;                 // output-channel tiles of the layer

parameter bw       = 4;
parameter psum_bw  = 16;
parameter col      = 8;
parameter row      = 8;
parameter len_kij  = 9;
parameter len_onij = 16;
parameter len_nij  = 36;
parameter ACC_BASE  = 1024;
parameter RELU_BASE = 1536;

localparam NC = NI*NO;
localparam XW = row*bw;
localparam PW = col*psum_bw;
localparam RA = IT/NI;            // itile rounds per core
localparam RB = OT/NO;            // otile rounds per core

reg clk = 0;
reg reset = 1;

wire [34:0] inst_q;

reg [NC*XW-1:0] D_xmem_q = 0;
reg CEN_xmem = 1, WEN_xmem = 1;
reg [10:0] A_xmem = 0;
reg CEN_xmem_q = 1, WEN_xmem_q = 1;
reg [10:0] A_xmem_q = 0;
reg CEN_pmem = 1, WEN_pmem = 1;
reg [10:0] A_pmem = 0;
reg CEN_pmem_q = 1, WEN_pmem_q = 1;
reg [10:0] A_pmem_q = 0;
reg ofifo_rd_q = 0, relu_q = 0, first_acc_q = 0, l0_rd_q = 0, l0_wr_q = 0;
reg execute_q = 0, load_q = 0, acc_q = 0, red_q = 0;

reg [NC*XW-1:0] D_xmem;
reg ofifo_rd, relu, first_acc, l0_rd, l0_wr, execute, load, acc, red;

wire ofifo_valid;
wire [NC*PW-1:0] sfp_out;

assign inst_q[34]    = red_q;
assign inst_q[33]    = acc_q;
assign inst_q[32]    = CEN_pmem_q;
assign inst_q[31]    = WEN_pmem_q;
assign inst_q[30:20] = A_pmem_q;
assign inst_q[19]    = CEN_xmem_q;
assign inst_q[18]    = WEN_xmem_q;
assign inst_q[17:7]  = A_xmem_q;
assign inst_q[6]     = ofifo_rd_q;
assign inst_q[5]     = relu_q;
assign inst_q[4]     = first_acc_q;
assign inst_q[3]     = l0_rd_q;
assign inst_q[2]     = l0_wr_q;
assign inst_q[1]     = execute_q;
assign inst_q[0]     = load_q;

multi_core #(.NI(NI), .NO(NO), .bw(bw), .col(col), .row(row)) dut (
  .clk(clk), .inst(inst_q), .ofifo_valid(ofifo_valid),
  .D_xmem(D_xmem_q), .sfp_out(sfp_out), .reset(reset));

// stimulus and golden data
reg [XW-1:0] act_mem  [0:IT*len_nij-1];             // [t*36 + nij]
reg [XW-1:0] w_mem    [0:IT*OT*len_kij*col-1];      // [((t*OT+u)*9+k)*8 + oc]
reg [PW-1:0] out_mem  [0:OT*len_onij-1];            // [u*16 + o]
reg [PW-1:0] pre_mem  [0:OT*len_onij-1];

integer fd, r, t, u, k, i, j, a, b, c, o, n_acc, kk;
integer error, checks;
reg [8*80:1] fname;
reg [8*80:1] token;
reg [XW-1:0] rd32;
reg [PW-1:0] rd128;

task skip_header(input integer f);
  integer h;
  begin
    for (h = 0; h < 3; h = h + 1) r = $fscanf(f, "%s", token);
  end
endtask

task load_files;
  begin
    for (t = 0; t < IT; t = t + 1) begin
      $sformat(fname, "activation_itile%0d.txt", t);
      fd = $fopen(fname, "r");
      if (fd == 0) begin $display("ERROR: cannot open %0s", fname); $finish; end
      skip_header(fd);
      for (i = 0; i < len_nij; i = i + 1) begin r = $fscanf(fd, "%32b", rd32); act_mem[t*len_nij + i] = rd32; end
      $fclose(fd);
      for (u = 0; u < OT; u = u + 1)
        for (k = 0; k < len_kij; k = k + 1) begin
          $sformat(fname, "weight_itile%0d_otile%0d_kij%0d.txt", t, u, k);
          fd = $fopen(fname, "r");
          if (fd == 0) begin $display("ERROR: cannot open %0s", fname); $finish; end
          skip_header(fd);
          for (i = 0; i < col; i = i + 1) begin r = $fscanf(fd, "%32b", rd32); w_mem[((t*OT+u)*len_kij+k)*col + i] = rd32; end
          $fclose(fd);
        end
    end
    for (u = 0; u < OT; u = u + 1) begin
      $sformat(fname, "out_otile%0d.txt", u);
      fd = $fopen(fname, "r");
      if (fd == 0) begin $display("ERROR: cannot open %0s", fname); $finish; end
      skip_header(fd);
      for (i = 0; i < len_onij; i = i + 1) begin r = $fscanf(fd, "%128b", rd128); out_mem[u*len_onij + i] = rd128; end
      $fclose(fd);
      $sformat(fname, "out_pre_relu_otile%0d.txt", u);
      fd = $fopen(fname, "r");
      if (fd == 0) begin $display("ERROR: cannot open %0s", fname); $finish; end
      skip_header(fd);
      for (i = 0; i < len_onij; i = i + 1) begin r = $fscanf(fd, "%128b", rd128); pre_mem[u*len_onij + i] = rd128; end
      $fclose(fd);
    end
  end
endtask

// one full clock (signals set before this call are latched on its posedge)
task tick;
  begin
    #0.5 clk = 1'b1;
    #0.5 clk = 1'b0;
  end
endtask

task do_reset;
  begin
    reset = 1;
    for (i = 0; i < 11; i = i + 1) tick;
    reset = 0;
    tick;
    tick;
  end
endtask

// compare SFP output of every reducing core (ci == 0) with the expected file
task check_out(input integer otile_round, input integer onij, input integer pre);
  reg [PW-1:0] got, exp;
  integer cc;
  begin
    for (cc = 0; cc < NO; cc = cc + 1) begin        // cores (0, cc)
      got = sfp_out[cc*PW +: PW];
      exp = pre ? pre_mem[(cc + NO*otile_round)*len_onij + onij]
                : out_mem[(cc + NO*otile_round)*len_onij + onij];
      checks = checks + 1;
      if (got !== exp) begin
        error = error + 1;
        $display("ERROR otile %0d onij %2d (%0s): got %h exp %h",
                 cc + NO*otile_round, onij, pre ? "pre-ReLU" : "post-ReLU", got, exp);
      end
    end
  end
endtask

// cycle counters
integer cycle = 0;
integer cyc_start, cyc_compute_end, cyc_end;
always @(posedge clk) cycle <= cycle + 1;

// main sequence
initial begin
  D_xmem = 0; ofifo_rd = 0; relu = 0; first_acc = 0; l0_rd = 0; l0_wr = 0;
  execute = 0; load = 0; acc = 0; red = 0;
  error = 0; checks = 0;

  if (IT % NI != 0 || OT % NO != 0 || NI > 2) begin
    $display("ERROR: bad configuration NI=%0d NO=%0d IT=%0d OT=%0d", NI, NO, IT, OT);
    $finish;
  end
  if (!$test$plusargs("NO_VCD")) begin
    $dumpfile("multi_core_tb.vcd");
    $dumpvars(0, multi_core_tb);
  end

  load_files;
  $display("multi_core_tb: NI=%0d NO=%0d (%0d cores), layer %0dx%0d ch, %0d itile x %0d otile rounds per core",
           NI, NO, NC, 8*IT, 8*OT, RA, RB);

  #0.5 clk = 1'b0;
  do_reset;
  cyc_start = cycle;

  // activations -> SRAM (each core: its itiles, addr a*36+nij)
  for (a = 0; a < RA; a = a + 1)
    for (t = 0; t < len_nij; t = t + 1) begin
      for (c = 0; c < NC; c = c + 1)
        D_xmem[c*XW +: XW] = act_mem[((c / NO) + NI*a)*len_nij + t];
      WEN_xmem = 0; CEN_xmem = 0; A_xmem = a*len_nij + t;
      tick;
    end
  WEN_xmem = 1; CEN_xmem = 1; A_xmem = 0;
  tick;

  for (b = 0; b < RB; b = b + 1) begin
    for (a = 0; a < RA; a = a + 1) begin
      for (kk = 0; kk < len_kij; kk = kk + 1) begin
        do_reset;

        // weights -> SRAM (addr 1024+)
        for (t = 0; t < col; t = t + 1) begin
          for (c = 0; c < NC; c = c + 1)
            D_xmem[c*XW +: XW] =
              w_mem[((((c / NO) + NI*a)*OT + ((c % NO) + NO*b))*len_kij + kk)*col + t];
          WEN_xmem = 0; CEN_xmem = 0; A_xmem = 11'd1024 + t;
          tick;
        end
        WEN_xmem = 1; CEN_xmem = 1; A_xmem = 0;
        tick;

        // weights SRAM -> L0
        for (t = 0; t < col+1; t = t + 1) begin
          if (t < col) begin CEN_xmem = 0; WEN_xmem = 1; A_xmem = 11'd1024 + t; end
          else               CEN_xmem = 1;
          if (t > 0) l0_wr = 1;
          tick;
        end
        l0_wr = 0; CEN_xmem = 1; A_xmem = 0;
        tick;

        // L0 -> PE weight registers
        for (t = 0; t < col; t = t + 1) begin
          l0_rd = 1; load = 1;
          tick;
        end
        load = 0; l0_rd = 0;
        tick;
        for (i = 0; i < 10; i = i + 1) tick;

        // activations SRAM -> L0
        for (t = 0; t < len_nij+1; t = t + 1) begin
          if (t < len_nij) begin CEN_xmem = 0; WEN_xmem = 1; A_xmem = a*len_nij + t; end
          else                     CEN_xmem = 1;
          if (t > 0) l0_wr = 1;
          tick;
        end
        l0_wr = 0; CEN_xmem = 1; A_xmem = 0;
        tick;

        // execute
        for (t = 0; t < len_nij; t = t + 1) begin
          l0_rd = 1; execute = 1;
          tick;
        end
        l0_rd = 0; execute = 0;
        tick;
        for (i = 0; i < row+col+2; i = i + 1) tick;

        // OFIFO -> psum SRAM
        for (t = 0; t < len_nij; t = t + 1) begin
          ofifo_rd = 1; CEN_pmem = 0; WEN_pmem = 0; A_pmem = (a*len_kij + kk)*len_nij + t;
          tick;
        end
        ofifo_rd = 0; CEN_pmem = 1; WEN_pmem = 1; A_pmem = 0;
        tick;
      end
    end
    if (b == 0) cyc_compute_end = cycle;

    // accumulation (+ reduction) + ReLU for this otile round
    n_acc = RA*len_kij;
    for (o = 0; o < len_onij; o = o + 1) begin
      for (j = 0; j < n_acc+1; j = j + 1) begin
        if (j < n_acc) begin
          a  = j / len_kij;
          kk = j % len_kij;
          CEN_pmem = 0; WEN_pmem = 1;
          A_pmem = (a*len_kij + kk)*len_nij
                 + ((o/4) + (kk/3))*6 + ((o%4) + (kk%3));
        end else begin
          CEN_pmem = 1; WEN_pmem = 1;
        end
        acc       = (j > 0);
        first_acc = (j == 1);
        tick;
      end
      acc = 0; first_acc = 0;
      if (NI == 2) begin                       // cross-core reduction cycle
        acc = 1; red = 1;
        tick;
        acc = 0; red = 0;
      end
      // write accumulated (pre-ReLU) result
      CEN_pmem = 0; WEN_pmem = 0; A_pmem = ACC_BASE + b*len_onij + o;
      tick;
      check_out(b, o, 1);
      // ReLU
      CEN_pmem = 1; WEN_pmem = 1; relu = 1;
      tick;
      // write ReLU result
      relu = 0; CEN_pmem = 0; WEN_pmem = 0; A_pmem = RELU_BASE + b*len_onij + o;
      tick;
      CEN_pmem = 1; WEN_pmem = 1; A_pmem = 0;
      tick;
      check_out(b, o, 0);
    end
  end
  cyc_end = cycle;

  $display("------------------------------------------------------------");
  $display("CONFIG NI=%0d NO=%0d cores=%0d  checks=%0d errors=%0d", NI, NO, NC, checks, error);
  $display("CYCLES total=%0d  (first otile round compute=%0d)", cyc_end - cyc_start, cyc_compute_end - cyc_start);
  if (error == 0) $display("############ No error detected ##############");
  else            $display("############ %0d errors ##############", error);
  $display("------------------------------------------------------------");

  for (t = 0; t < 10; t = t + 1) tick;
  $finish;
end

// register all controls/data once more (same convention as core_tb.v)
always @(posedge clk) begin
  D_xmem_q    <= D_xmem;
  CEN_xmem_q  <= CEN_xmem;
  WEN_xmem_q  <= WEN_xmem;
  A_xmem_q    <= A_xmem;
  CEN_pmem_q  <= CEN_pmem;
  WEN_pmem_q  <= WEN_pmem;
  A_pmem_q    <= A_pmem;
  ofifo_rd_q  <= ofifo_rd;
  acc_q       <= acc;
  red_q       <= red;
  relu_q      <= relu;
  first_acc_q <= first_acc;
  l0_rd_q     <= l0_rd;
  l0_wr_q     <= l0_wr;
  execute_q   <= execute;
  load_q      <= load;
end

endmodule
