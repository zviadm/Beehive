`timescale 1ns / 1ps
`define SOL4

/* 
* Barrier Module
*
* To enter a barrier, a core reads AQ[2:0] = 6.
* The unit sends a barrier slot on the ring, and enters waitBarrier state.
* 
* If the unit receives a barrier slot, it increments count, regardless of 
* its current state.
* 
* If count is equal to ethercore, then the unit returns 1 in RQ, and 
* switches to state idle and resets count.
* 
* All barrier slots are totally ordered on the ring, so there is never any
* confusion about which generation of the barrier is currently running.
* 
*/

module Barrier(
  //signals common to all local I/O devices:
  input clock,
  input reset,
//  input [8:3]  aq, //the CPU address queue output.
//  input read,      //request in AQ is a read
//  output [31:0] rqBarrier, //the CPU read queue input
//  output wrq,      //write the read queue
  output done,     //operation is finished. Read the AQ
  input selBarrier,  // XXX
  input [3:0] whichCore,
  input [3:0] EtherCore,
  input msgrWaiting,
  input lockerWaiting,

  //ring signals
  input  [31:0] RingIn,
  input  [3:0]  SlotTypeIn,
  input  [3:0]  SrcDestIn,
  output [31:0] barrierRingOut,
  output [3:0]  barrierSlotTypeOut,
  output [3:0]  barrierSrcDestOut,
  output        barrierDriveRing,
  output        barrierWaiting
);

`ifdef SOL4   

  reg [2:0] state;  // barrier FSM
  reg [7:0] burstLength; // length of the train
  reg [4:0] count;  // number of cores that reached barrier
   
  parameter idle = 0;  //states
  parameter waitToken = 2;
  parameter waitN = 3;
  parameter send = 4;
  parameter waitBarrier = 5;

  parameter Null = 7; //Slot Types
  parameter Token = 1;
  parameter Barrier = 13;
   
   
//-------------------------------End of Declarations----------------------------

  wire nBarrierCoresMinusOne = EtherCore - 4'd3;

  assign done = selBarrier & 
                (SlotTypeIn == Barrier) & (count == nBarrierCoresMinusOne);

  assign barrierWaiting = (state == waitToken);
   
  assign barrierDriveRing =
    ((state == waitToken) & (SlotTypeIn == Token)) |  //to add to the train.
    (state == send) |  //send Barrier message
    ((SlotTypeIn == Barrier) & (SrcDestIn == whichCore)); //drive NULL
   
  assign barrierSlotTypeOut = 
    //replace my barrier with Null
    (((SlotTypeIn == Barrier) & (SrcDestIn == whichCore))) ? Null :  
    (state == send) ? Barrier :  // Barrier
    SlotTypeIn;
   
  assign barrierRingOut = 
    ((state == waitToken) & (SlotTypeIn == Token)) ? (RingIn + 1) :
    (state == send) ? {32'b0} :  // Barrier message contains nothing
    RingIn;
   
  assign barrierSrcDestOut = (state == send) ? whichCore : SrcDestIn;
   
  always @(posedge clock) begin
    if (SlotTypeIn == Barrier) begin
      if (count == nBarrierCoresMinusOne) count <= 0;
      else count <= count + 1;
    end
  end
   
  always @(posedge clock) begin
    if (reset) state <= idle;
    else case(state)      
      idle: 
        if (selBarrier) state <= waitToken;  // need to send barrier slot
               
      waitToken: 
        if ((SlotTypeIn == Token) & ~msgrWaiting & ~lockerWaiting) begin
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

      send: // send the barrier slot
        state <= waitBarrier;          // wait for barrier

      waitBarrier:
        if ((SlotTypeIn == Barrier) & (count == nBarrierCoresMinusOne)) begin
          state <= idle;
        end
    endcase
  end
`endif

endmodule // Barrier

