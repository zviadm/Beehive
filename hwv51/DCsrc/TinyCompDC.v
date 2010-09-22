
`timescale 1ns / 1ps

module TinyCompDC(
 input Ph0,    //50 Mhz clock
 input Reset,
// output [7:0] LED,
 inout DVIscl,
 inout DVIsda
 );

/* This is a version of the TC customized to run the Display controller.

The data memory is a 64 * 32 LUT RAM, since (at the moment), it
only contains the stack.
*/

wire doSkip;
wire [31:00] WD; //write data to the register file
wire [31:00] RFAout; //register file port A read data
wire [31:00] RFBout; //register file port B read data
reg  [9:0]   PC;
wire [9:0]   PCinc, PCinc2, PCmux;
wire [31:00] ALU;
wire [31:00] ALUresult;
wire [31:00] DM; //the Data memory (1K x 32) output
wire [31:00] IM; //the Instruction memory (1K x 32) output 

wire [2:0] Opcode;
wire [4:0] Ra, Rw;
wire [10:0] Rb;
wire Normal, RbConst, IO, Load, Store, /* StoreI, */ Jump; //Opcode decodes
wire [2:0] Skip;
wire Skn, Skz, Ski, Skge, Sknz, Skni, Skp;
wire [1:0] Rcy;
wire NoCycle, Rcy1, Rcy8;
wire [2:0] Funct;
wire AplusB, AminusB, Bplus1, Bminus1, AandB, AorB, AxorB;
wire WriteRF;

wire [31:0] Ain, Bin; //ALU inputs

wire InReady;
wire [31:0] InValue;
//reg [7:0] LEDs;

wire [3:0] IOaddr;  //16 IO devices for now.
//wire writeLED;

wire readTimer;
wire writeTimer;  //refresh timer (single event)
wire writeTimerReload; //refresh timer (continuous events)
wire timerReady;

reg SCLx;
reg SDAx;
wire SDAin;
(* KEEP = "TRUE" *) reg SDAinReg;
(* KEEP = "TRUE" *) wire writeI2C;


//---------------the I/O devices---------------

always @(posedge Ph0) SDAinReg <= SDAin;

//Pin buffers for SDA, SCL
  OBUFT sclBuf(.O(DVIscl), .I(1'b0), .T(~SCLx));
  IOBUF sdaBuf(.IO(DVIsda), .O(SDAin), .I(1'b0), .T(~SDAx));


assign IOaddr  = Rb[4:1];  //device addresses are constants.

assign InReady = ~Rb[0] &  timerReady; //Rb[0] == 0 is "Input"
					  
assign InValue = {31'b0, SDAin};
 
assign readTimer = ~Rb[0] & (IOaddr == 3) & IO;

assign writeI2C =         Rb[0] & (IOaddr == 1) & IO;
//assign writeLED =         Rb[0] & (IOaddr == 2) & IO;
assign writeTimer =       Rb[0] & (IOaddr == 3) & IO;
assign writeTimerReload = Rb[0] & (IOaddr == 4) & IO;

//always @(posedge Ph0) if(writeLED) LEDs <= RFAout[7:0];
//assign LED = LEDs;

always @(posedge Ph0) if(writeI2C) begin
  SDAx <= RFAout[0];
  SCLx <= RFAout[1];
end  

 
 Timer timex(
  .Ph0(Ph0),
  .reset(Reset),
  .countValue(RFAout[23:0]),
  .readRef(readTimer),
  .writeRef(writeTimer),
  .writeRefReload(writeTimerReload),
  .refReady(timerReady)
  );  
 
 //---------------------- The CPU ------------------------
	
  always @(posedge Ph0)
  if(Reset) PC <= 0;
  else PC <= PCmux;

//Opcode fields
assign Rw = IM[31:27];
assign Ra = IM[26:22];
assign Rb = IM[21:11];  //larger than needed to address RF.
assign Funct = IM[10:8];
assign Rcy = IM[7:6];
assign Skip = IM[5:3];
assign Opcode = IM[2:0];

//Opcodes
assign Normal  = Opcode == 0;
assign RbConst = Opcode == 1;
assign IO      = Opcode == 2;
assign Load    = Opcode == 3;
assign Store   = Opcode == 4;
//assign StoreI  = Opcode == 5;
assign Jump    = Opcode == 6;
//assign Const   = Opcode == 7;

//Skips
assign Skn =  (Skip == 1);
assign Skz =  (Skip == 2);
assign Ski =  (Skip == 3);
assign Skge = (Skip == 4);
assign Sknz = (Skip == 5);
assign Skni = (Skip == 6);
assign Skp  = (Skip == 7);

//Cyclic shifts
assign NoCycle = (Rcy == 0);
assign Rcy1 =    (Rcy == 1);
assign Rcy8 =    (Rcy == 2);


//ALU functions
assign AplusB =   Funct == 0;
assign AminusB =  Funct == 1;
assign Bplus1 =   Funct == 2;
assign Bminus1 =  Funct == 3;
assign AandB =    Funct == 4;
assign AorB  =    Funct == 5;
assign AxorB =    Funct == 6;



//The Skip Tester.
assign doSkip =
 (Normal | RbConst | IO) &  //Opcode can skip
   ( 
    (Skn & ALU[31]) |
    (Skz & (ALU == 0)) |
	 (Ski & InReady) |
	 (Skge & ~ALU[31]) |
	 (Sknz & (ALU != 0)) |
	 (Skni & ~InReady) |
	 Skp
	);
 
//The PC-related signals
 assign PCinc =  PC + 1;
 assign PCinc2 = PC + 2;
 assign PCmux = 
   Jump ? ALU[10:0] :
   (Load & (Rw == 31)) ? DM[10:0] :  //subroutine return
	doSkip ? PCinc2 :
	PCinc;
                

//Instantiate the WD multiplexer.
assign WD =
  (Normal | RbConst | Store /* | StoreI */ ) ? ALU :
  IO ? InValue:
  Load ?  DM:
  Jump ?  {21'b0, PCinc}:
  {8'b0, IM[26:3]};  // 24- bit constant  

assign WriteRF = (Rw != 0); //Writes to r0 are discarded.

//The input multiplexers for the ALU inputs
 assign Ain = (Ra == 31) ? {21'b0, PC} : RFAout;
 
 assign Bin = ( RbConst | Jump ) ? {21'b0, Rb} : RFBout;
 
//Instantiate the ALU: An adder/subtractor followed by a shifter
 assign ALUresult = 
   AplusB  ? Ain + Bin :
	AminusB ? Ain - Bin :
	Bplus1  ? Bin + 1 :
	Bminus1 ? Bin - 1 :
   AandB ? Ain & Bin :
	AorB  ? Ain | Bin :
	AxorB ? Ain ^ Bin :
	Ain & ~Bin;  //A and not B

 assign ALU = 
   NoCycle ? ALUresult :
   Rcy1 ? {ALUresult[0], ALUresult[31:1]} :
   Rcy8 ? {ALUresult[7:0], ALUresult[31:8]} :
   {ALUresult[15:0], ALUresult[31:16]};


//Instantiate the instruction memory.  A 1K x 32 ROM.
imromDC im (
	.clka(Ph0),
	.addra(PCmux), 
	.douta(IM));

	
//Instantiate the data memory. A simple single-port RAM.
ramy dm (
	.a(RFBout[5:0]),  
	.d(RFAout), 
	.clk(Ph0),
	.we(Store),
	.spo(DM)); 

//Instantiate the register file.  This has three independent addresses, so two RAMs are needed.
ramz rfA(
  .a(Rw),
  .d(WD), //write port
  .dpra(Ra),
  .clk(Ph0),
  .we(WriteRF),
  .spo(),
  .dpo(RFAout) //read port
	);

 ramz rfB(
  .a(Rw),
  .d(WD),
  .dpra(Rb[4:0]),
  .clk(Ph0),
  .we(WriteRF),
  .spo(),
  .dpo(RFBout)  //read port
  );
endmodule
/*
module Timer(
 input Ph0,
 input reset,
 input [23:0] countValue, //timer countdown value
 input readRef,
 input writeRef, //one event
 input writeRefReload, //run continuosly
 output reg refReady
 );
 
 reg [23:0] refCount, refValue;
 reg refArmed, refReload;
 
 always @(posedge Ph0) //refArmed
   if(reset | ((refCount == 0) & refArmed & ~refReload)) refArmed <= 0;
	else if(writeRef | writeRefReload) refArmed <= 1;

 always @(posedge Ph0) //refReady
   if(reset | (readRef & refReady)) refReady <= 0; //clear when read
	else if ((refCount == 0) & refArmed) refReady <= 1;
	
 always @(posedge Ph0) if(writeRef) refReload <= 0; else if(writeRefReload) refReload <= 1;
	
 always @(posedge Ph0) if(writeRef | writeRefReload) refValue <= countValue;
 
 always @(posedge Ph0) 
   if (writeRef | writeRefReload) refCount <= countValue;
	else if((refCount == 0) & refArmed & refReload) refCount <= refValue;
	else if (refCount != 0) refCount <= refCount - 1; //count down
	
endmodule
*/
