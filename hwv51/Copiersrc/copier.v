`timescale 1ns / 1ps
module copier(
 input  reset,
 input  clock, //clock
 input  [3:0]  whichCore,  //the number of this core


/* The block copier is similar to the Ethernet controller,
in that it is a node on the Ring, and has a RISC to
process messages for its clients.  The RISC sets
up the three registers that control the transfer:
S(the 31-bit source word address), 
D(the 31-bit destination word address),
and L (the number of words remaining in the source region).

The copier does word-aligned transfers,
using an intermediate buffer to assemble the destination
data.

The controller currently only doe non-overlapping source
and destination regions.

It could be made faster by providing a 128-bit back-door
path to the memory, but since it can transfer one cache line
per token, it should be fast enough.

*/
 
 //Ring signals
 input  [31:0] RingIn,
 input  [3:0]  SlotTypeIn,
 input  [3:0]  SrcDestIn,
 output [31:0] RingOut,
 output [3:0]  SlotTypeOut,
 output [3:0]  SrcDestOut,
 input  [31:0] RDreturn,
 input  [3:0]  RDdest,

//signals between the copier and the display controller. 
 inout DVIscl,
 inout DVIsda,
 input verticalFP,
 output [25:0] displayAddress
 
);

reg [5:0] wa; //write address for the buffer ram
reg [5:0] ra; //read address for the buffer ram
reg [2:0] bCnt; //buffer count (8 buffers).  Incremented when
//a buffer is filled, decremented when a buffer is written to memory.
reg [30:0] S; //source word address (for BEE3)
reg [30:0] D; //destination word address
reg [30:0] L; //transfer length
reg [2:0]  rcnt; //word number during a read transfer
reg [3:0]  state;   //control machine
reg [2:0]  RCfsm; //ring control machine
reg readRequested, writeRequested;
reg [7:0] burstLength;
reg [16:0] checksum;
wire [16:0] interA;
wire [16:0] interB;

wire readIssued;
wire [31:0] readAddress;
wire [31:0] writeAddress;
wire [31:0] bufData; //output of buffer memory
wire [31:0] wq;      //RISC write queue
wire loadS;
wire loadD;
wire loadL;
wire [16:0] chkBusy;    //controller is busy
wire [31:0] msgrRingOut;
wire [3:0] msgrSlotTypeOut;
wire [3:0] msgrSrcDestOut;
wire msgrDriveRing;
wire msgrWaiting;
wire readRequest;
wire writeRequest;
wire decBcnt;
wire incBcnt;
wire writeBufFromSrc;
wire writeBufFromDest;

parameter idle = 0;
parameter fetchD = 1; //fetch from D
parameter waitD = 2;  //wait for D data
parameter fetchS = 3; //fetch first source block
parameter waitS = 4; //wait for first source
parameter fetchS1 = 5; //fetch remaining source lines
parameter waitS1 = 6;   //wait for read data
parameter waitWriteFetchD1 = 7;  //wait for writes to complete, go to fetchD1
parameter fetchD1 = 8; //fetch last destination line (if needed)
parameter waitD1 = 9;  //wait for last destination data
parameter waitFinalWrite = 10;  //wait for the final write to finish

 parameter RCidle = 0;
 parameter RCwaitToken = 1;
 parameter RCwaitN = 2;
 parameter RCsendBoth = 3;
 parameter RCsendRAonly = 4;
 parameter RCsendWA = 5;
 parameter RCsendData = 6; 

parameter Null = 7; //Slot Types
 parameter Token = 1;
 parameter Address = 2;
 parameter WriteData = 3;
 parameter Message = 8;
 parameter Lock = 9;
 parameter LockFail = 10;
 
 
//--------------------------End of declarations--------------------

assign chkBusy = { ~checksum[15:0], ~(state == idle)};
//if bit 0 = 0, the controller is idle and the checksum is valid

assign writeBufFromSrc = (RDdest == whichCore) & (L != 0) & 
  (
    ((state == waitS) & (rcnt >= S[2:0])) | //fetching the first source word.
    (state == waitS1)
  );
  
assign writeBufFromDest = (RDdest == whichCore) &
  (
  (state == waitD)  |  //Write the entire block, even though the final words may be overwritten.
  ((state == waitD1) & (rcnt >= wa)) //Fill in the final block with destination data.
  );

assign writeBuf = writeBufFromSrc | writeBufFromDest;

assign writeRequest = (bCnt != 0);

assign readRequest = (bCnt < 5) &  //don't overfill buffer
 ( 
  (state == fetchD) |
  (state == fetchS) |
  (state == fetchS1)|
  (state == fetchD1)
 );

assign readIssued = (RCfsm == RCsendRAonly) | (RCfsm == RCsendBoth);

always @(posedge clock) if(loadS)   wa <= 0;
 else if((state == fetchS) & readIssued) wa <= {3'b0, D[2:0]}; //Unaligned destination, reset wa.
 else if(writeBuf) wa <= wa + 1;

assign readBuf = (RCfsm == RCsendData);
 
always @(posedge clock) if(loadS) ra <= 0;
 else if(readBuf) ra <= ra + 1;

assign incBcnt = (
  ((wa[2:0] == 7) & writeBufFromSrc) |   //normal case when full block written 
  ((state == waitS) & (rcnt == 7) & (L == 0)) |  //block ended befort the first block is full
  ((state == waitD1) & (rcnt == 7))  //final block filled from destination.
 );
  
assign decBcnt = (RCfsm == RCsendWA);
  
always @(posedge clock) if(reset | loadS) bCnt <= 0;
  else if(incBcnt & ~decBcnt) bCnt <= bCnt + 1;
  else if(decBcnt & ~incBcnt) bCnt <= bCnt - 1;
  
always @(posedge clock) if (loadS)
  S <= wq[30:0];
  else if(writeBufFromSrc) S <= S + 1;
 
always @(posedge clock) if (loadD)
  D <= wq[30:0];
  else if(RCfsm == RCsendWA) D <= D + 8;
 
always @(posedge clock) if (loadL) L <= wq[30:0];
 else if(writeBufFromSrc) L <= L - 1;

always @(posedge clock) if (reset) rcnt <= 0;
  else if(RDdest == whichCore) rcnt <= rcnt + 1;

//The ring controller is identical to the one in the Ethernet
//-------------------The ring controller FSM:----------------------
always @(posedge clock)
  if(reset) RCfsm <= RCidle;
  else case(RCfsm)
    RCidle:if(readRequest | writeRequest) begin
	    readRequested <= readRequest;
		 writeRequested <= writeRequest;
   	 RCfsm <= RCwaitToken; //have something to do
    end

	 RCwaitToken: if((SlotTypeIn == Token) & ~msgrWaiting) begin
       if(RingIn[7:0] == 0) begin  //empty train
         if(readRequested & ~writeRequested) RCfsm <= RCsendRAonly;
			else if(writeRequested & ~readRequested) begin
			  burstLength <= 8;
           RCfsm <= RCsendData;
			end else RCfsm <= RCsendBoth; //read and write
		 end else begin  //must wait.
			burstLength <= RingIn[7:0];
			RCfsm <= RCwaitN;
		 end
    end

    RCwaitN: begin  //wait for the end of the train
	   burstLength <= burstLength - 1;
		if(burstLength == 1) begin
        if(readRequested & ~writeRequested) RCfsm <= RCsendRAonly;
		  else if(writeRequested & ~readRequested) begin
		    burstLength <= 8;
          RCfsm <= RCsendData;
        end else RCfsm <= RCsendBoth;
      end		  
    end
	 
	 RCsendRAonly: RCfsm <= RCidle; //send RA, idle

	 RCsendBoth: begin
	    burstLength <= 8;
       RCfsm <= RCsendData; //send RA, then send WD and WA
	 end
	 
	 RCsendData: begin
	   burstLength <= burstLength - 1;
		if(burstLength == 1) RCfsm <= RCsendWA;
	 end
	 
	 RCsendWA: begin
		RCfsm <= RCidle;
	 end
  endcase


//------------------The main FSM------------------
always @(posedge clock) 
  if(reset) state <= idle;
  else case (state)

  idle:
  if(L != 0) 
    if((D[2:0] != 0) | (L <= 8)) state <= fetchD;  //dest not cache aligned | L <= 8
    else state <= fetchS;

  fetchD:
  if(readIssued) state <= waitD;

  waitD:
  if(rcnt == 7) state <= fetchS;

  fetchS:  //fetch first source block
  if(readIssued) state <= waitS;

  waitS:  //Wait for first source block to arrive.
/*
When rcnt == 7, the last word of the block is on RDreturn.
There are several cases:

1a) L > 1:  More source words are needed. Fetch them.
bCnt will be incremented and the buffer written whenever
a buffer block boundary is crossed (wa[2:0] == 7) & writeBufFromSrc).

1b) (L == 1) & (wa[2:0] == 7):  The transfer ended exactly on a 
destination block boundary.  The buffer will be written (and 
bCnt incremented) at the end of the cycle.  We go to waitFinalWrite
to wait for the write to finish, and when bCnt == 0, we idle.

1c) (L == 1) & (wa[2:0] != 7).  In this case, the transfer extended
into the second buffer block (wa[2:0] will be between 0 and
7 after the buffer is written and bCnt is incremented).

bCnt will be incremented to write the first block, 
but we must wait for the write to finish,
then fetch the last destination block to fill in the rest of the
second block. We go to waitWriteFetchD1.

1d) (L == 0): In this case, the transfer ended before the end of the 
buffer block.  We increment bCnt and go to waitFinalWrite.

The difference between the first block of a transfer and subsequent
blocks is that in the latter, we must always fetch the last destination
block to fill out the final block unless the transfer ends precisely
on a block boundary.  For the first block, the destination was
fetched before the first source block was read, so we don't need to do this.

The conditions for waitS are:
  if(rcnt == 7) 
    if(L > 1) state <= fetchS1; //case 1a
	 else if (L == 1) begin
	   if(wa[2:0] == 7) state <= waitFinalWrite; //case 1b
		else state <= waitWriteFetchD1; //case 1c 
	end
	else state <= waitFinalWrite;  //case 1d

This is simplified as shown below.
*/
  if(rcnt == 7)
    if(L > 1) state <= fetchS1; //case 1a
    else if((L == 1) & (wa[2:0] != 7)) state <= waitWriteFetchD1; //case 1c
    else state <= waitFinalWrite; //cases 1b, 1d  	 

  fetchS1:
   if(readIssued) state <= waitS1;
  
  waitS1:  //Wait for read data for blocks other than the first.
/*
When rcnt == 7, if L < = 1, we don't need any more source words (if
L > 1, we definitely need more, and if (L == 1), the buffer will
be written, bCnt incremented, and L decremented to zero
at the end of the cycle).
*/
  if (rcnt == 7)
    if (L > 1)  state <= fetchS1; //We need at least one more source word.
    else if((L == 1) & (wa[2:0] == 7)) state <= waitFinalWrite;
	 else state <= waitWriteFetchD1;  //bCnt is not incremented yet.  It happens at the end of waitD1.

  waitWriteFetchD1:
    if(bCnt == 0) state <= fetchD1;
	 
  fetchD1:
    if (readIssued) state <= waitD1;
	 
  waitD1:
    if (rcnt == 7) state <= waitFinalWrite;
  
  waitFinalWrite:
  if (bCnt == 0) state <= idle;
  
  endcase
  
//-------------Ring contents-------------------------------------
  assign readAddress = ((state == fetchD) | (state == fetchD1)) ?  {4'b0001, D[30:3]}: {4'b0001, S[30:3]};
  
  assign writeAddress = {4'b0000, D[30:3]};
  
  assign SrcDestOut =
      msgrDriveRing ? msgrSrcDestOut :
     ((RCfsm == RCsendRAonly) | 
	  (RCfsm == RCsendBoth) | 
	  (RCfsm == RCsendWA) |
	  (RCfsm == RCsendData)) ? whichCore :
     SrcDestIn;
	  
  assign RingOut =
     msgrDriveRing ? msgrRingOut :
     ((RCfsm == RCwaitToken) & (SlotTypeIn == Token)) ? (RingIn + (writeRequested? 9 : 0) + readRequested) :
     ((RCfsm == RCsendRAonly) | (RCfsm == RCsendBoth)) ? readAddress :
	  (RCfsm == RCsendWA) ? writeAddress :
	  (RCfsm == RCsendData) ? bufData :
      RingIn;
		
  assign SlotTypeOut =
     msgrDriveRing ? msgrSlotTypeOut : 
    ((RCfsm == RCsendRAonly) | (RCfsm == RCsendBoth) | (RCfsm == RCsendWA))? Address :
    (RCfsm == RCsendData) ? WriteData :	 
     SlotTypeIn;


//instantiate the buffer
bufRAM64x32 buffer (
	.a(wa), // Bus [5 : 0] 
	.d(RDreturn), // Bus [31 : 0] 
	.dpra(ra), // Bus [5 : 0] 
	.clk(clock),
	.we(writeBuf),
	.spo(), // Bus [31 : 0] 
	.dpo(bufData)); // Bus [31 : 0]

	
//Instantiate the RISC
DCcopyRISC controlRisc(
 .reset(reset),
 .clock(clock),
 .whichCore(whichCore),
 .RingIn(RingIn),
 .SlotTypeIn(SlotTypeIn),
 .SrcDestIn(SrcDestIn),
 .msgrSlotTypeOut(msgrSlotTypeOut),
 .msgrSrcDestOut(msgrSrcDestOut),
 .msgrRingOut(msgrRingOut),
 .msgrDriveRing(msgrDriveRing),
 .msgrWaiting(msgrWaiting),
// .RxD(RxD),
// .TxD(TxD),
// .releaseRS232(releaseRS232),
 .wq(wq),
 .loadSA(loadS),
 .loadDA(loadD),
 .loadCnt(loadL),
 .chkBusy(chkBusy),
 .DVIscl(DVIscl),
 .DVIsda(DVIsda),
 .verticalFP(verticalFP),
 .displayAddress(displayAddress)

 );

//a 16-bit 1's complement checksum generator.


assign interA = {1'b0,RDreturn[15:0]} + {1'b0,checksum[15:0]} + checksum[16];
assign interB = {1'b0, RDreturn[31:16]} + {1'b0, interA[15:0]} + interA[16];
always @(posedge clock) if(reset | loadS) checksum <= 0;
  else if(writeBufFromSrc) checksum <= interB;
  else if((state == waitFinalWrite) & (bCnt == 0) & checksum[16]) checksum <= checksum + 1; //add any final carry  


 
endmodule
