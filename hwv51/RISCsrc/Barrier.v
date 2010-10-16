`timescale 1ns / 1ps

/* 
* Barrier Module
*
* To enter a barrier, a core reads AQ[2:0] = 6.
* The unit sends a barrier slot on the ring, and enters waitBarrier state.
* 
* If the unit receives a barrier slot, it increments count, regardless of 
* its current state.
* 
* If count is equal to number of application cores, then the unit returns 
* the control to the CPU switches to state idle and resets count.
* 
* All barrier slots are totally ordered on the ring, so there is never any
* confusion about which generation of the barrier is currently running.
* 
*/

module Barrier(
  //signals common to all local I/O devices:
  input clock,
  input reset,
  output done,     //operation is finished. Read the AQ
  input selBarrier,
  input [3:0] whichCore,

  //ring signals
  input  [31:0] RingIn,
  input  [3:0]  SlotTypeIn,
  input  [3:0]  SourceIn,
  output [31:0] barrierRingOut,
  output [3:0]  barrierSlotTypeOut,
  output [3:0]  barrierSourceOut,
  output barrierDriveRing,
  output barrierWantsToken,
  input  barrierAcquireToken
);

  reg [1:0] state;  // barrier FSM
  reg [4:0] count;  // number of cores that reached barrier
   
  localparam idle = 0;  //states
  localparam waitToken = 2;
  localparam waitBarrier = 3;
      
//-------------------------------End of Declarations----------------------------

  wire [3:0] nBarrierCoresMinusOne = `nCores - 4'd2;

  // Barrier is done when it receives last Barrier message
  assign done = selBarrier & 
                (SlotTypeIn == `Barrier) & (count == nBarrierCoresMinusOne);

  // Intercations with the ring
  assign barrierWantsToken = (state == waitToken);   
  assign barrierDriveRing = (state == waitToken) & (barrierAcquireToken);
  assign barrierSlotTypeOut = `Barrier;
  assign barrierSourceOut = whichCore;
  assign barrierRingOut = 32'b0;
   
  always @(posedge clock) begin
    if (reset) count <= 0;
    else if (SlotTypeIn == `Barrier) begin
      if (count == nBarrierCoresMinusOne) count <= 0;
      else count <= count + 4'b1;
    end
  end
   
  always @(posedge clock) begin
    if (reset) state <= idle;
    else case(state)      
      idle: if (selBarrier) state <= waitToken;
      waitToken: if (barrierAcquireToken) state <= waitBarrier; 
      waitBarrier: // wait for barrier messages
        if ((SlotTypeIn == `Barrier) & (count == nBarrierCoresMinusOne))
          state <= idle;
    endcase
  end
endmodule

