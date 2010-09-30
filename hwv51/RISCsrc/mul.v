`timescale 1ns / 1ps

module mul (
 input clock,
 input reset,
 input [31:0] wq, //the CPU write queue output
 output rwq,      //read the write queue
 output [31:0] rq, //the CPU read queue input
 output wrq,      //write the read queue
 output done,     //operation is finished. Read the AQ.
 input selMul
 );

/* 
This is a pipelined 32 X 32 multiplier using the DSP48E.

The RISC places a and b in the write queue and writes IObase + 1 into the address queue (write).
The multiplier loads ar on the cycle in which selMul == true & count == 7.
It loads br in the cycle in which             selMul == true & count == 0.
The next 7 cycles do the multiply.

Count controls the multiplexing of the data into the DSP and the opcode issued to the DSP.

Here is the pipeline:

count    mul inputs   X  Y  Z         M <=         P <=
7: (ar <=)
0: (br <=)
1:      arL, brL      M  M  0         arL * brL    -
2:      arH, brL      M  M  0         arH * brL    (arL + brL) + 0
3:      arL, brH      M  M  p rsh 17  arL * brH    (arH * brL) + msb(p)  (lsb(p2)) valid)
4:      arH, brL      M  M  p         arH * brH    (arL + brH) + p3
5:                          p rsh 17   -     -     (arH * brH) + msb(p4) (lsb(p4) valid)
6: (done = true)                                                                       (p4 valid)                             
           
Bits 16:0  (17 bits)  of the 64-bit product is available on prod during count = 3
bits 34:17 (17 bits) of the 64-bit product are available on prod during count = 5, and
bits 63:35 (28 bits  of the 64-bit product are available during count = 6.

The counter then sticks at 7 until the next operation starts.
The read queue is written when count == 3 or count == 5.
*/

reg  [31:0] ar, br; //operands
reg  [2:0]  count;
wire [47:0] prod; //DSP output
reg  [16:0] prodReg; //17 bits
wire [29:0] aIn; //DSP input a - 30 bits
wire [17:0] bIn; //DSP input b - 18 bits
wire [6:0]  opcode; //DSP opcode 

//---------------------end of declarations --------------------

always @ (posedge clock)
  if(reset) count <= 7;
  else if(selMul) count <= count + 1;
  
assign done = (count == 6);

always @ (posedge clock)
  if(selMul & (count == 7)) ar <= wq;
  else if(count == 0) br <= wq;

assign opcode = ((count == 1) | (count == 2)) ? 7'b0000101 : //z = 0 
                (count == 4) ? 7'b0100101 :                  //z = p
					 7'b1100101;                                  //z = p rsh 17

assign rwq = (selMul & (count == 7)) | (count == 0);
										 
assign aIn = ((count == 1) | (count == 3)) ? {13'b0, ar[16:0]} : // low 17 bits zero-extended to 30 bits
             {{15{ar[31]}}, ar[31:17]}; //high 15 bits extended to 30 bits.

assign bIn = ((count == 1) | (count == 2)) ? { 1'b0, br[16:0]} : //low 17 bits zero extended to 18 bits
   {{3{br[31]}}, br[31:17]}; //high 15 bits sign-extended to 18 bits.

always @ (posedge clock)
   if((count == 3) |(count == 5)) prodReg <= prod[16:0]; //17 bits

assign wrq = (count == 5) | (count == 6);

//The 64 bit product is valid in cycle 5 and 6. RQ is written.
assign rq = (count == 5) ? {prod[14:0], prodReg[16:0]} : //low 15 + 17 = 32 bits of product
            (count == 6) ?{prod[29:0], prodReg[16:15]} : //high 32 product bits
				32'b0;

DSP48E #(
   .ACASCREG(0),       
   .ALUMODEREG(1),     
   .AREG(0),           
   .AUTORESET_PATTERN_DETECT("FALSE"),     // "FALSE" (cjt -- fix modelsim complaint
   .AUTORESET_PATTERN_DETECT_OPTINV("MATCH"), 
   .A_INPUT("DIRECT"), 
   .BCASCREG(0),       
   .BREG(0),           
   .B_INPUT("DIRECT"), 
   .CARRYINREG(0),     
   .CARRYINSELREG(1),  
   .CREG(0),           
   .MASK(48'h3FFFFFFFFFFF), 
   .MREG(1),           
   .MULTCARRYINREG(0), 
   .OPMODEREG(0),      
   .PATTERN(48'h000000000000), 
   .PREG(1),           
   .SEL_MASK("MASK"),  
   .SEL_PATTERN("PATTERN"), 
   .SEL_ROUNDING_MASK("SEL_MASK"), 
   .USE_MULT("MULT_S"), 
   .USE_PATTERN_DETECT("NO_PATDET"), 
   .USE_SIMD("ONE48") 
) 
DSP48E_1 (
   .ACOUT(),   
   .BCOUT(),  
   .CARRYCASCOUT(), 
   .CARRYOUT(), 
   .MULTSIGNOUT(), 
   .OVERFLOW(), 
   .P(prod),          
   .PATTERNBDETECT(), 
   .PATTERNDETECT(), 
   .PCOUT(),  
   .UNDERFLOW(), 
   .A(aIn),          
   .ACIN(30'b0),    
   .ALUMODE(4'b0000), 
   .B(bIn),          
   .BCIN(18'b0),    
   .C(48'b0),          
   .CARRYCASCIN(1'b0), 
   .CARRYIN(1'b0), 
   .CARRYINSEL(3'b0), 
   .CEA1(1'b0),      
   .CEA2(1'b0),      
   .CEALUMODE(1'b1), 
   .CEB1(1'b0),      
   .CEB2(1'b0),      
   .CEC(1'b0),      
   .CECARRYIN(1'b0), 
   .CECTRL(1'b1), 
   .CEM(1'b1),       
   .CEMULTCARRYIN(1'b0),
   .CEP(1'b1),       
   .CLK(clock),       
   .MULTSIGNIN(1'b0), 
   .OPMODE(opcode), 
   .PCIN(),      
   .RSTA(reset),     
   .RSTALLCARRYIN(reset), 
   .RSTALUMODE(reset), 
   .RSTB(reset),     
   .RSTC(reset),     
   .RSTCTRL(reset), 
   .RSTM(reset), 
   .RSTP(reset) 
);

endmodule





