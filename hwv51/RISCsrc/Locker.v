`timescale 1ns / 1ps
module Locker(
//signals common to all local I/O devices:
  input clock,
  input reset,
  input [8:3]  aq, //the CPU address queue output.
  input read,      //request in AQ is a read
  output [31:0] rqLock, //the CPU read queue input
  output wrq,      //write the read queue
  output done,     //operation is finished. Read the AQ
  input selLock,
  input [3:0] whichCore,
  input msgrWaiting,
  
//ring signals
 input  [31:0] RingIn,
 input  [3:0]  SlotTypeIn,
 input  [3:0]  SrcDestIn,
 output [31:0] lockRingOut,
 output [3:0]  lockSlotTypeOut,
 output [3:0]  lockSrcDestOut,
 output        lockDriveRing,
 output lockerWaiting,
 output reg lockHeld
 );


/* The lock unit contains a 64 x 1 dual-ported LUT RAM with a one-bit entry
for each of the system-wide locks.
To acquire a lock, a core reads AQ[2:0] = 5 with the lock number in AQ[8:3].
If the indicated bit is set in the lock RAM, the read returns RQ = 1 immediately.
Otherwise, a lock request slot  is sent on the ring.
If another core holds the lock, it converts the lock request into a “lock fail” 
slot type before forwarding it.  If the requesting core receives the unmodified request,
it sets the lock bit and returns 1 in RQ. If it receives lock fail,
it returns 0 and the lock bit is not modified.
To release a lock, the core writes AQ[2:0] = 5 with the lock number in AQ[8:3].
The indicated lock bit is cleared.
*/

 reg [2:0]   state;  //lock FSM
 reg [7:0]   burstLength; //length of the train
 wire writeLock;
 wire lockD;   //lock memory din
 wire locked;  //addressed by aq
 wire ringLock; //addressed by RingIn[5:0]

 parameter idle = 0;  //states
 parameter waitToken = 2;
 parameter waitN = 3;
 parameter send = 4;
 parameter waitSF = 5;
 
 parameter Null = 7; //Slot Types
 parameter Token = 1;
 parameter Lock = 9;
 parameter LockFail = 10;
 
//------------------End of Declarations-----------------------

 always @(posedge clock) begin
   if(reset |((state == idle) & selLock & ~read & (aq[8:3] == 1)))  lockHeld <= 0;  //core releases lock
	else if((state == waitSF) & (SlotTypeIn == Lock) & (SrcDestIn == whichCore) & (RingIn[5:0] ==1)) lockHeld <= 1;  //core acquires lock
 end
	
	
 assign lockerWaiting = (state == waitToken);
 
 always @(posedge clock) begin
  if(reset) state <= idle;
  else case(state)
  
   idle: if(selLock & read & ~locked ) state <= waitToken;  //need to try for the lock
	
	waitToken: if((SlotTypeIn == Token) & ~msgrWaiting) begin
     if(RingIn[7:0] == 0) state <= send;
	  else begin
		 burstLength <= RingIn[7:0];
		 state <= waitN;
	  end
   end
	
   waitN: begin  //wait for the end of the train
	       burstLength <= burstLength - 1;
			 if(burstLength == 1) state <= send;
    end
	 
	 send: //send the lock request
	   state <= waitSF;          //wait for success or failure
		
	 waitSF:
	   if(((SlotTypeIn == LockFail) | (SlotTypeIn == Lock)) & (SrcDestIn == whichCore)) state <= idle;
 endcase
 end

 assign done = ((state == idle) & selLock & ~read) |  //Release the lock.
   ((state == idle) & selLock & read & locked) |  //request for a lock we already hold
   ((state == waitSF) & (SrcDestIn == whichCore) &
	((SlotTypeIn == Lock) | (SlotTypeIn == LockFail))); //Request returned after one ring transit				

 assign rqLock = {31'b0, (((state == idle) & selLock & read & locked) | ((state == waitSF) & (SrcDestIn == whichCore) & (SlotTypeIn == Lock)))};

// assign wrq = done & read;
   assign wrq =
     ((state == idle) & selLock & read & locked) |
     ((state == waitSF) & (SrcDestIn == whichCore) & ((SlotTypeIn == Lock) | (SlotTypeIn == LockFail)));
	  
// assign writeLock = done;
   assign writeLock =
	  ((state == idle) & selLock & ~read) |  //Release the lock.
     ((state == waitSF) & (SrcDestIn == whichCore) & ((SlotTypeIn == Lock) | (SlotTypeIn == LockFail)));  //set or clear
	  
//lock is set it when Lock returns unscathed or when a lock request is for a lock that
//is already held.  It is cleared by an IO write to the lock unit.
 assign lockD =  
	((state == waitSF) & (SrcDestIn == whichCore) & (SlotTypeIn == Lock));
   
 assign lockDriveRing =
   ((state == waitToken) & (SlotTypeIn == Token)) |  //to add to the train.
   (state == send) |  //send Lock request 
   (((SlotTypeIn == Lock) | (SlotTypeIn == LockFail)) & (SrcDestIn == whichCore)) | //My request or release returns.  Drive Null.
   ((SlotTypeIn == Lock) & (SrcDestIn != whichCore) & ringLock);  //A lock request request from another core for a lock that I hold.  Drive LockFail 
 
 assign lockSlotTypeOut = 
    (((SlotTypeIn == Lock) | (SlotTypeIn == LockFail)) & (SrcDestIn == whichCore)) ? Null :  //replace my Lock or LockFail with Null
    ((SlotTypeIn == Lock) & (SrcDestIn != whichCore) & ringLock) ? LockFail :  //a request from another core for a lock that I hold.  Send LockFail
	 (state == send) ? Lock :  //Lock request
    SlotTypeIn;
	 
 assign lockRingOut = ((state == waitToken) & (SlotTypeIn == Token)) ? (RingIn + 1) :
                      (state == send) ? {24'b0, aq[8:3]} :  //lock request  Drive Lock number.
							 RingIn;
							 
 assign lockSrcDestOut = (state == send) ? whichCore : SrcDestIn;

lockMem Locker (
	.a(aq[8:3]), 
	.d(lockD), 
	.dpra(RingIn[5:0]), 
	.clk(clock),
	.we(writeLock),
	.spo(locked), 
	.dpo(ringLock)); 

endmodule
