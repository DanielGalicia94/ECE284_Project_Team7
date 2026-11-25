// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
`timescale 1ns/1ps

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

reg clk = 0;
reg reset = 1;

wire [33:0] inst_q; 

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

// Model masks are active-high, bit 0 = original channel 0.
reg [row-1:0] input_mask;
reg [col-1:0] output_mask;
wire [row-1:0] hw_row_enable;
wire [col-1:0] hw_col_enable;
integer pad_pruned, bypass_mask, arg_status;
reg [8*256-1:0] header_line;
reg [8*512-1:0] vcd_file_name;
reg [bw*row-1:0] x_ref [0:len_nij-1];
reg [bw*row-1:0] w_ref [0:len_kij*col-1];
reg [10:0] ref_addr [0:len_kij*len_onij-1];
reg [psum_bw*col-1:0] golden_raw [0:len_onij-1];
reg [psum_bw*col-1:0] golden_relu [0:len_onij-1];
integer r_ref, c_ref, p_ref, k_ref, x_index, kernel_index, addr_ref;
integer x_value, w_value, sum_ref, active_rows, active_cols;
reg signed [bw-1:0] signed_weight;
integer cycles = 0;
always @(posedge clk) begin
  cycles <= cycles + 1;
  if (!reset && ofifo_rd_q && ofifo_valid !== 1'b1)
    $fatal(1, "OFIFO read while not valid (cycle %0d)", cycles);
end
assign hw_row_enable = bypass_mask ? {row{1'b1}} : input_mask;
assign hw_col_enable = bypass_mask ? {col{1'b1}} : output_mask;

// The input files contain exactly three comment/header lines (except addresses).
task skip_header;
  input integer fd;
  integer h, rc;
  begin
    for (h=0; h<3; h=h+1) begin
      rc = $fgets(header_line, fd);
      if (rc == 0) $fatal(1, "Missing stimulus header");
    end
  end
endtask

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


core  #(.bw(bw), .col(col), .row(row)) core_instance (
	.clk(clk), 
	.inst(inst_q),
	.ofifo_valid(ofifo_valid),
    .D_xmem(D_xmem_q), 
    .sfp_out(sfp_out), 
	.reset(reset),
    .row_enable(hw_row_enable),
    .col_enable(hw_col_enable)); 


initial begin 

  input_mask = {row{1'b1}};
  output_mask = {col{1'b1}};
  arg_status = $value$plusargs("INPUT_MASK=%h", input_mask);
  arg_status = $value$plusargs("OUTPUT_MASK=%h", output_mask);
  pad_pruned = $test$plusargs("PAD_PRUNED");
  bypass_mask = $test$plusargs("MASK_BYPASS");
  if (bypass_mask && !pad_pruned)
    $fatal(1, "MASK_BYPASS requires PAD_PRUNED for equivalent outputs");
  if (row != 8 || col != 8 || bw != 4 || psum_bw != 16 || len_kij != 9)
    $fatal(1, "Masking testbench retains the baseline 8x8, 4-bit, nine-offset configuration");
  active_rows = 0;
  active_cols = 0;
  for (r_ref=0; r_ref<row; r_ref=r_ref+1) active_rows = active_rows + input_mask[r_ref];
  for (c_ref=0; c_ref<col; c_ref=c_ref+1) active_cols = active_cols + output_mask[c_ref];
  $display("INPUT_MASK=%h OUTPUT_MASK=%h model-active PEs=%0d hardware-enabled PEs=%0d PAD_PRUNED=%0d MASK_BYPASS=%0d",
           input_mask, output_mask, active_rows*active_cols,
           bypass_mask ? row*col : active_rows*active_cols, pad_pruned, bypass_mask);
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

  if (!$test$plusargs("NO_VCD")) begin
    vcd_file_name = "core_tb.vcd";
    arg_status = $value$plusargs("VCD_FILE=%s", vcd_file_name);
    $dumpfile(vcd_file_name);
    $dumpvars(0,core_tb);
  end

  x_file = $fopen("activation_tile0.txt", "r");
  acc_file = $fopen("acc_address.txt", "r");
  if (x_file == 0 || acc_file == 0) $fatal(1, "Cannot open activation/address stimulus files");
  skip_header(x_file);

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

  /////// Activation data writing to memory ///////
  for (t=0; t<len_nij; t=t+1) begin  
    #0.5 clk = 1'b0;
    x_scan_file = $fscanf(x_file,"%b", D_xmem);
    if (x_scan_file != 1) $fatal(1, "Invalid activation at index %0d", t);
    x_ref[t] = D_xmem; // capture original values for independent reference
    if (pad_pruned)
      for (r_ref=0; r_ref<row; r_ref=r_ref+1)
        if (!input_mask[r_ref]) D_xmem[r_ref*bw +: bw] = 0;
    WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1;
    #0.5 clk = 1'b1;   
  end

  #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
  #0.5 clk = 1'b1; 

  $fclose(x_file);
  /////////////////////////////////////////////////


  for (kij=0; kij<9; kij=kij+1) begin  // kij loop

    case(kij)
     0: w_file_name = "weight_itile0_otile0_kij0.txt";
     1: w_file_name = "weight_itile0_otile0_kij1.txt";
     2: w_file_name = "weight_itile0_otile0_kij2.txt";
     3: w_file_name = "weight_itile0_otile0_kij3.txt";
     4: w_file_name = "weight_itile0_otile0_kij4.txt";
     5: w_file_name = "weight_itile0_otile0_kij5.txt";
     6: w_file_name = "weight_itile0_otile0_kij6.txt";
     7: w_file_name = "weight_itile0_otile0_kij7.txt";
     8: w_file_name = "weight_itile0_otile0_kij8.txt";
    endcase
    

    w_file = $fopen(w_file_name, "r");
    if (w_file == 0) $fatal(1, "Cannot open %0s", w_file_name);
    skip_header(w_file);

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





    /////// Kernel data writing to memory ///////

    A_xmem = 11'b10000000000;

    for (t=0; t<col; t=t+1) begin  
      #0.5 clk = 1'b0;
      w_scan_file = $fscanf(w_file,"%b", D_xmem);
      if (w_scan_file != 1) $fatal(1, "Invalid weight at kernel %0d output %0d", kij, t);
      w_ref[kij*col+t] = D_xmem;
      if (pad_pruned)
        for (r_ref=0; r_ref<row; r_ref=r_ref+1)
          if (!input_mask[r_ref] || !output_mask[t]) D_xmem[r_ref*bw +: bw] = 0;
      WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1;
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
    #0.5 clk = 1'b1; 
    /////////////////////////////////////



    /////// Kernel data writing to L0 ///////
    A_xmem = 11'b10000000000;
    
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



    /////// Kernel loading to PEs ///////
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



    /////// Activation data writing to L0 ///////
    A_xmem = 11'b00000000000;
    
    for (t=0; t<len_nij+1; t=t+1) begin
        #0.5 clk = 1'b0;
        if (t<len_nij) begin CEN_xmem = 0; WEN_xmem = 1; if (t>0) A_xmem = A_xmem + 1; end
        else       begin CEN_xmem = 1; end
        if (t>0)   begin l0_wr = 1'b1; end
        #0.5 clk = 1'b1;
    end
    #0.5 clk = 1'b0; l0_wr = 0; CEN_xmem = 1; A_xmem = 0;
    #0.5 clk = 1'b1;
    /////////////////////////////////////



    /////// Execution ///////
    for (t=0; t<len_nij; t=t+1) begin
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
    // Ideally, OFIFO should be read while execution, but we have enough ofifo
    // depth so we can fetch out after execution.
    for (t=0; t<len_nij; t=t+1) begin
        #0.5 clk = 1'b0; ofifo_rd = 1; CEN_pmem = 0; WEN_pmem = 0; A_pmem = kij*len_nij + t;
        #0.5 clk = 1'b1;
    end
    #0.5 clk = 1'b0; ofifo_rd = 0; CEN_pmem = 1; WEN_pmem = 1; A_pmem = 0;
    #0.5 clk = 1'b1;
    /////////////////////////////////////


    $fclose(w_file);
  end  // end of kij loop


  ////////// Independent golden convolution /////////
  // Address file specifies which (kernel position, input pixel) to accumulate.
  // Decode it in the reference independently of PE scheduling and SFP arithmetic.
  for (addr_ref=0; addr_ref<len_onij*len_kij; addr_ref=addr_ref+1) begin
    acc_scan_file = $fscanf(acc_file,"%b", ref_addr[addr_ref]);
    if (acc_scan_file != 1 || ref_addr[addr_ref] >= len_kij*len_nij)
      $fatal(1, "Invalid accumulation address at index %0d", addr_ref);
  end
  for (p_ref=0; p_ref<len_onij; p_ref=p_ref+1) begin
    golden_raw[p_ref] = 0;
    golden_relu[p_ref] = 0;
    for (c_ref=0; c_ref<col; c_ref=c_ref+1) begin
      sum_ref = 0;
      if (output_mask[c_ref]) begin
        for (k_ref=0; k_ref<len_kij; k_ref=k_ref+1) begin
          addr_ref = ref_addr[p_ref*len_kij+k_ref];
          kernel_index = addr_ref / len_nij;
          x_index = addr_ref % len_nij;
          for (r_ref=0; r_ref<row; r_ref=r_ref+1) begin
            if (input_mask[r_ref]) begin
              x_value = x_ref[x_index][r_ref*bw +: bw]; // unsigned activation
              signed_weight = w_ref[kernel_index*col+c_ref][r_ref*bw +: bw];
              w_value = signed_weight; // sign-extend before integer multiply
              sum_ref = sum_ref + x_value*w_value;
            end
          end
        end
      end
      if (sum_ref < -(1 << (psum_bw-1)) || sum_ref > (1 << (psum_bw-1))-1)
        $fatal(1, "Golden psum overflows %0d bits", psum_bw);
      golden_raw[p_ref][c_ref*psum_bw +: psum_bw] = sum_ref;
      golden_relu[p_ref][c_ref*psum_bw +: psum_bw] = (sum_ref < 0) ? 0 : sum_ref;
    end
  end

  // The supplied golden file is only valid for the original all-enabled model.
  // Cross-check it in the default regression; masked cases use the computed golden.
  // CHECK_OUT_FILE allows comparison against a separately exported pruned golden.
  if (((&input_mask) && (&output_mask)) || $test$plusargs("CHECK_OUT_FILE")) begin
    out_file = $fopen("out.txt", "r");
    if (out_file == 0) $fatal(1, "Cannot open baseline out.txt");
    skip_header(out_file);
    for (p_ref=0; p_ref<len_onij; p_ref=p_ref+1) begin
      out_scan_file = $fscanf(out_file,"%b", answer);
      if (out_scan_file != 1 || answer !== golden_relu[p_ref])
        $fatal(1, "Supplied golden differs at position %0d", p_ref);
    end
    $fclose(out_file);
  end
  error = 0;

  $display("############ Verification Start during accumulation #############"); 

  for (i=0; i<len_onij+1; i=i+1) begin 

    #0.5 clk = 1'b0; 
    #0.5 clk = 1'b1; 

    if (i>0) begin
     answer = golden_relu[i-1];
       if (sfp_out === answer)
         $display("%2d-th output featuremap Data matched! :D", i); 
       else begin
         $display("%2d-th output featuremap Data ERROR!!", i); 
         $display("sfpout: %128b", sfp_out);
         $display("answer: %128b", answer);
         error = error + 1;
       end
    end
    
    if (i<len_onij) begin
        //Accumulation
        for (j=0; j<len_kij+1; j=j+1) begin 
            #0.5 clk = 1'b0;   
            if (j<len_kij) begin CEN_pmem = 0; WEN_pmem = 1; A_pmem = ref_addr[i*len_kij+j]; end
            else  begin CEN_pmem = 1; WEN_pmem = 1; end
    
            if (j>0)  acc = 1;
            if (j==1) first_acc = 1; else first_acc = 0;
            #0.5 clk = 1'b1;   
        end
        //write back to psum
        #0.5 clk = 1'b0; acc = 0; first_acc = 0; CEN_pmem = 0; WEN_pmem = 0; A_pmem = ACC_BASE + i;
        #0.5 clk = 1'b1; 
        //relu
        #0.5 clk = 1'b0;
        if (sfp_out !== golden_raw[i]) begin
          $display("PRE-ReLU mismatch at position %0d: actual=%h expected=%h", i, sfp_out, golden_raw[i]);
          error = error + 1;
        end
        CEN_pmem = 1; WEN_pmem = 1; relu = 1;
        #0.5 clk = 1'b1; 
        //write back
        #0.5 clk = 1'b0; relu = 0; CEN_pmem = 0; WEN_pmem = 0; A_pmem = RELU_BASE + i;
        #0.5 clk = 1'b1; 
    
        #0.5 clk = 1'b0; CEN_pmem = 1; WEN_pmem = 1; A_pmem = 0;
        #0.5 clk = 1'b1; 
    end
  end  
    

  if (error == 0) begin
  	$display("############ No error detected ##############"); 
  	$display("########### Project Completed !! ############"); 

  end

  $fclose(acc_file);
  $display("Checked %0d positions, pre/post ReLU; errors=%0d; cycles=%0d (through last comparison, including setup)", len_onij, error, cycles+1);
  if (error != 0) $fatal(1, "Masked convolution verification failed");
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
end


endmodule




