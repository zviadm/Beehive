`timescale 1ns / 1ps

/* 
This unit provides 64 binary semaphores.  It replaces the earlier
lock unit, which provided 64 mutexes.

The sem unit contains a 64 x 1 dual-ported LUT RAM with a one-bit entry
for each of the system-wide semaphores.

To do a P (Wait), a core reads AQ[2:0] = 5 with the semaphore number in AQ[8:3].
If the indicated bit is set in the lock RAM, the read returns RQ = -1 immediately (Andrew's case (a)).
Otherwise, a Preq  is sent on the ring.

If another core holds the semaphore, it converts the Preq into a Pfail 
slot type before forwarding it.  If the requesting core receives the unmodified request,
it sets the semaphore bit and returns 1 in RQ (Andrew's case (b)). If it receives Pfail,
it returns 0 and the semaphore bit is not modified (Andrew's case (c)).

To do a V (Signal), the core writes AQ[2:0] = 5 with the semaphore number in AQ[8:3].
If the semaphore bit is set, it is cleared and the operation does not cause any ring activity.
If the bit is cleared, the unit waits for a token and injects a V slot into the ring.
When any other unit receives a V directed to a semaphore that it holds, it clears the selected semaphore
bit.

The "otherV" signal is asserted when a Vreq slot arrives from another core.

Signal always has priority over the core's activity for writing the lock RAM.  The ram is dual-ported,
with a mux on the address which selects RingIn[5:0] if otherV, else AQ[8:3].  The second read
port is used to check whether the sem is held when a Preq arrives from another core. 
*/

module Sem(
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
  
  //ring signals
  input  [31:0] RingIn,
  input  [3:0]  SlotTypeIn,
  input  [3:0]  SourceIn,
  output [31:0] lockRingOut,
  output [3:0]  lockSlotTypeOut,
  output [3:0]  lockSourceOut,
  output lockDriveRing,
  output lockWantsToken,
  input  lockAcquireToken
);

  reg [1:0] state;  //lock FSM
  wire writeLock;
  wire lockD;   //lock memory din
  wire locked;  //addressed by lockAddr
  wire ringLock; //addressed by RingIn
  wire otherV;
  wire [5:0] lockAddr;

  localparam idle = 0;  //states
  localparam waitToken = 2;
  localparam waitSF = 3;

//------------------End of Declarations-----------------------

  assign otherV = (SlotTypeIn == `Vreq) & (SourceIn != whichCore);
 
  assign lockAddr = otherV ? RingIn[5:0] : aq[8:3];

  assign done = 
    //Signal or wait on a sem we hold.
    ((state == idle) & selLock  & ~otherV & locked) |  
    //send the V.
    ((state == waitToken & (lockAcquireToken)) & ~read) |
    //Preq returned after one ring transit
    ((state == waitSF) & (SourceIn == whichCore) & 
     ((SlotTypeIn == `Preq) | (SlotTypeIn == `Pfail)));

  assign rqLock = 
    ((state == idle) & selLock & read & ~otherV & locked) ? 32'h00000002 :
    ((state == waitSF) & (SourceIn == whichCore) & 
     (SlotTypeIn == `Preq)) ? 32'h00000001 : 
    32'h00000000;

  assign wrq = done & read;
  
  //lock is set it when Preq returns unscathed.
  //It is cleared by a Signal or an otherV.
  assign writeLock = 
    ((state == idle) & selLock & ~read) |  //Signal
    (otherV) |
    ((state == waitSF) & (SourceIn == whichCore) & 
     ((SlotTypeIn == `Preq) | (SlotTypeIn == `Pfail)));  //set or clear

  assign lockD = 
    ((state == waitSF) & (SourceIn == whichCore) & (SlotTypeIn == `Preq));
   
  // interactions with the ring
  assign lockWantsToken = (state == waitToken);
  assign lockDriveRing =
    //send Preq or Vreq 
    ((state == waitToken) & (lockAcquireToken)) | 
    //A Preq from another core for a sem that I hold.  Drive Pfail 
    ((SlotTypeIn == `Preq) & (SourceIn != whichCore) & ringLock);
 
  assign lockSlotTypeOut = 
    ((state == waitToken) & (lockAcquireToken) & read) ? `Preq :  //send Preq
    ((state == waitToken) & (lockAcquireToken) & ~read) ? `Vreq : //send Vreq
    //a Preq from another core for a sem that I hold.  Send PFail
    ((SlotTypeIn == `Preq) & (SourceIn != whichCore) & ringLock) ? `Pfail : 
    `Null;
 
  assign lockRingOut = 
    //lock request. Drive Lock number.
    ((state == waitToken) & (lockAcquireToken)) ? {26'b0, aq[8:3]} : RingIn;
  assign lockSourceOut = 
    ((state == waitToken) & (lockAcquireToken)) ? whichCore : SourceIn;

  // Lock Unit FSM
  always @(posedge clock) begin
    if(reset) state <= idle;
    else case(state)
      idle: if (selLock & ~otherV & ~locked) 
        state <= waitToken; //Wait or Signal on a sem we don't hold.

      waitToken: if (lockAcquireToken) begin
        if (read) state <= waitSF; //wait for success or failure of the P.
        else state <= idle;        //send the V (Signal)
      end
      
      waitSF: 
        if(((SlotTypeIn == `Preq) | (SlotTypeIn == `Pfail)) & 
           (SourceIn == whichCore)) 
          state <= idle;
    endcase
  end

  lockMem Locker (
    .a(lockAddr), 
    .d(lockD), 
    .dpra((SlotTypeIn == `Preq) ? RingIn[5:0] : 6'b0), 
    .clk(clock),
    .we(writeLock),
    .spo(locked), 
    .dpo(ringLock)
  ); 
endmodule
