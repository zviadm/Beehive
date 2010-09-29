`timescale 1ns / 1ps
/*
   RD Delayer Module. Delays returning of RDreturn signal by DELAY_CYCLES.      
   Delay Queue: FWFT 148x64 fifo
   
   Created By: Zviad Metreveli
*/
module RDDelayer(
   input clock,
   input reset,
   
   input [127:0] RD,
   input [3:0] dest,
   input rdDelayedRD,
   output reg [31:0] delayedRD,
   output reg [3:0] delayedDest
);
   // Wires to delayIn queue
   wire wrDelayQ;
   reg rdDelayQ;
   wire delayQempty;
   wire [147:0] delayQout;

   // counters
   reg [15:0] cycleCounter;
   reg [1:0] outputCounter;
      
   // FSM
   reg state, next_state;
   
   parameter DELAY_CYCLES = 1000;
   
   localparam idle = 0;
   localparam outputDelayedRD = 1;

   assign wrDelayQ = (dest != 0);      
   
   always @(posedge clock) begin
      if (reset) begin
         cycleCounter <= 0;
         state <= idle;
      end
      else begin   
         cycleCounter <= cycleCounter + 1;
         state <= next_state;
         
         if (next_state == outputDelayedRD) begin
            if (rdDelayedRD) outputCounter <= outputCounter + 1;
         end else outputCounter <= 0;
      end      
   end
      
   // Simple FSM transitions and outputs
   always @(*) begin
      // default values
      next_state = idle;
      rdDelayQ = 0;
      delayedDest = 0;
      delayedRD = 0;
      
      case (state)
         idle: begin
            if (~delayQempty && (cycleCounter - delayQout[147:132] >= DELAY_CYCLES)) begin
               next_state = outputDelayedRD;

               delayedDest = delayQout[131:128];
               delayedRD = ((outputCounter[1:0] == 0) ? delayQout[31:0] :
                            (outputCounter[1:0] == 1) ? delayQout[63:32] :
                            (outputCounter[1:0] == 2) ? delayQout[95:64] : delayQout[127:96]);
            end
            else next_state = idle;
         end
         
         outputDelayedRD: begin
            if ((outputCounter[1:0] == 3) && rdDelayedRD) begin
               rdDelayQ = 1;
               next_state = idle;
            end
            else next_state = outputDelayedRD;            
            
            delayedDest = delayQout[131:128];
            delayedRD = ((outputCounter[1:0] == 0) ? delayQout[31:0] :
                         (outputCounter[1:0] == 1) ? delayQout[63:32] :
                         (outputCounter[1:0] == 2) ? delayQout[95:64] : delayQout[127:96]);
         end
      endcase
   end
   
   // Delay Queue
   delayQ delayQueue (
      .clk(clock),
      .rst(reset),
      // When new RD is received, we store in the queue RD, dest and cycle that the RD was received.         
      .din({cycleCounter, dest, RD}),
      .wr_en(wrDelayQ),
      .rd_en(rdDelayQ),
      .dout(delayQout),
      .full(),
      .empty(delayQempty));      
endmodule
