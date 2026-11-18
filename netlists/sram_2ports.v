module sram_2ports (CLK, D_A, CEN_A, WEN_A, A_A, D_B, Q_B, CEN_B, WEN_B, A_B);

    parameter sram_bit = 128;
    parameter width = 16;
    //Port A for ofifo
    input  CLK;
    input  CEN_A;
    input  WEN_A;
    input  [sram_bit-1:0] D_A;
    input  [3:0] A_A;
    //Port B for sfp
    input  CEN_B;
    input  WEN_B;        
    input  [sram_bit-1:0] D_B;
    input  [3:0] A_B;
    output reg [sram_bit-1:0] Q_B;

    // reg [sram_bit-1:0] memory0;
    // reg [sram_bit-1:0] memory1;
    // reg [sram_bit-1:0] memory2;
    // reg [sram_bit-1:0] memory3;
    // reg [sram_bit-1:0] memory4;
    // reg [sram_bit-1:0] memory5;
    // reg [sram_bit-1:0] memory6;
    // reg [sram_bit-1:0] memory7;
    // reg [sram_bit-1:0] memory8;
    // reg [sram_bit-1:0] memory9;
    // reg [sram_bit-1:0] memory10;
    // reg [sram_bit-1:0] memory11;
    // reg [sram_bit-1:0] memory12;
    // reg [sram_bit-1:0] memory13;
    // reg [sram_bit-1:0] memory14;
    // reg [sram_bit-1:0] memory15;
    reg [sram_bit-1:0] mem [0:15];

    // Pipeline registers for read path (breaks A_A -> Q_B critical path)
    reg [3:0] A_A_reg;
    reg read_en_reg;
    initial read_en_reg = 0;

    always @ (posedge CLK) begin
        A_A_reg <= A_A;
        read_en_reg <= (!CEN_A && WEN_A);

        if (read_en_reg) begin
            Q_B <= mem[A_A_reg];
        end

        if (!CEN_A && !WEN_A) begin
            mem[A_A] <= D_A;
        end

        if (!CEN_B && !WEN_B) begin
            mem[A_B] <= D_B;
        end
    end
endmodule
