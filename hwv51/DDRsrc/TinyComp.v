
`timescale 1ns / 1ps

module TinyComp(
 input Ph0,    //50 Mhz clock
 input Reset,
 output [7:0] LED,
 input RxD,
 output TxD,
 
  //Signals to the memory controller:
 output [33:0]  LastALU,  //constructed from the MemValue register and the rank/bank bits.
 output reg injectTC5address,  //one-cycle signal signifying that LastALU is valid.
 //static control signals from the MemOut register:
 output reg StartDQCal0,
 output reg InhibitDDR,
 output reg DDRclockEnable,
 output reg ResetDDR,
 output reg Force,
 input CalFailed,
 
 //RS232 signals
 output reg [3:0] SelectRS232,
 input ReleaseRS232
);

/* This is a version of the TC customized to run the DDR2 controller,
replacing the TC5.  It is somewhat simpler than the TC5, in that it
doesn't use the event trigger mechanism.  It is a 32-bit machine.

The data memory is a 64 * 32 LUT RAM, since (at the moment), it
only contains the stack.

The memory controller receives a number of single-bit control 
signals, plus a 34-bit value on LastALU.  The bits of LastALU are:

       altAddr: {4'b0, LastALU[7:0], 2'b0}; //col address
		 //note bit 8 is not used.
       bank: LastALU[11:9];			
       addr: LastALU[25:12];        		//row address
       rank: LastALU[26];    //one bit on XUPv5, two bits (27:26) on BEE3
       cmd:  LastALU[30:28];
       altCmd: LastALU[33:31];

We want the TC to be a drop-in replacement for the TC5, so we
will supply the same 34 bit value.  However we note that TC5
never supplies a value with bits 7:0 != 0, so we can supply
zero for these bits.
		 
This leaves 6 bits of cmd/altcmd, 14 bits of row address, plus the
bank and rank bits.

We generate the latter in the MemOut
register, which is r29. Writes to this register are overloaded; 
writes to r29 also load MemOut from the ALU result.
Note that MemOut is never actually instantiated.  Only the individual
bits are.

The control bits and the rank and bank bits are bits in MemOut.
Doing it in this way makes it easy to set/clear individual bits using "|" 
and "&~".

Here's the assignment to LastALU:
  assign LastALU = {MemValue[19:14], 1'b0, rank, MemValue[13:0], bank[2:0], 9'b0}
                      6            ,  1  ,   1 ,   14           ,     3    , 9
So MemValue is 20 bits long.

The MemValue is an ordinary IO register (addressed with Rb, loaded
from Ra).

The calFailed signal is provided as an InReady skip condition.
 
*/
reg [19:0] MemValue;
reg [2:0] bank;
reg rank;

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
reg [7:0] LEDs;

wire [3:0] IOaddr;  //16 IO devices for now.
wire readRX;
wire charReady;
wire [7:0] RXchar;
wire writeLED;
wire writeTX;
wire readTX;
wire TXempty;
wire [7:0] TXchar;

wire readTimer;
wire writeTimer;  //refresh timer (single event)
wire writeTimerReload; //refresh timer (continuous events)
wire timerReady;

wire writeMemValue;
wire writeMemOut;
wire readMem;
wire writeSelRS232;


//---------------the I/O devices---------------

assign IOaddr  = Rb[4:1];  //device addresses are constants.

assign InReady = ~Rb[0] &  //Rb[0] == 0 is "Input"
  ((readRX & charReady) |  //read RS232 RX
   (readTX & TXempty)) |   //read RS232 TX
	(readTimer & timerReady) | //read Timer
	(readMem & CalFailed);   //memory calibration failed
					  
assign InValue = (IOaddr == 0) ? {24'b0, RXchar} :  32'b0;
assign TXchar  = RFAout[7:0];
 
assign readRX  =   ~Rb[0] & (IOaddr == 0) & IO;
assign readTX  =   ~Rb[0] & (IOaddr == 1) & IO;
assign readTimer = ~Rb[0] & (IOaddr == 3) & IO;
assign readMem   = ~Rb[0] & (IOaddr == 5) & IO;

assign writeTX =          Rb[0] & (IOaddr == 1) & IO;
assign writeLED =         Rb[0] & (IOaddr == 2) & IO;
assign writeTimer =       Rb[0] & (IOaddr == 3) & IO;
assign writeTimerReload = Rb[0] & (IOaddr == 4) & IO;
assign writeMemValue =    Rb[0] & (IOaddr == 5) & IO;
assign writeSelRS232 =    Rb[0] & (IOaddr == 6) & IO;

always @(posedge Ph0) if (Reset | ReleaseRS232) SelectRS232 <= 0;
 else if(writeSelRS232) SelectRS232 <= RFAout[3:0];

assign writeMemOut = (Rw == 29);

always @(posedge Ph0) if(writeMemValue) begin
  MemValue <= RFAout[19:0];
  injectTC5address <= 1'b1;
 end else injectTC5address <= 1'b0;

always @(posedge Ph0) if(writeMemOut) begin
  StartDQCal0 <= ALU[0];
  InhibitDDR <= ALU[1];
  DDRclockEnable <= ALU[2];
  ResetDDR <= ALU[3];
  Force <= ALU[4];
  rank <= ALU[5];
  bank <= ALU[8:6];
 end

assign LastALU = {MemValue[19:14], 1'b0, rank, MemValue[13:0], bank[2:0], 9'b0};

always @(posedge Ph0) if(writeLED) LEDs <= RFAout[7:0];
assign LED = LEDs;

rs232a user(
 .clock(Ph0),
 .reset(Reset),
 .readRX(readRX),
 .charReady(charReady),
 .RXchar(RXchar),

 .writeTX(writeTX), 
 .TXempty(TXempty),
 .TXchar(TXchar),
 .TxD(TxD),
 .RxD(RxD)
 );
 
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
imrom im (
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

