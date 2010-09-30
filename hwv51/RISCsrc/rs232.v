`timescale 1ns / 1ps

//  Copyright Microsoft Corporation, 2008

module rs232 #(parameter bitTime = 868) (
//signals common to all local I/O devices:
  input clock, //125 MHz clock
  input reset,
  input read,      //request in AQ is a read
  input [9:0] wq, //the CPU write queue output
  output rwq,      //read the write queue
  output [31:0] rq, //the CPU read queue input
  output wrq,      //write the read queue
  output done,     //operation is finished. Read the AQ.
//signals specific to the RS232 interface
  input selRS232,
  input a3,  
  input RxD, //received serial data
  output TxD, //transmit serial data
  input [3:0] whichCore,    //returned as bits 13:10 of rq
  input [3:0] EtherCore     //returned as bits 17:14 of rq  
);

wire runCounter;
wire midBit;
wire readSR;
wire writeTx;
reg [10:0] bitCounter;
reg [10:0] txCounter; //one bit time
reg [3:0] bitCnt; //transmit bit counter
reg [8:0] txData; //transmit shift register
wire txReady;     //transmitter is empty
reg [9:0] sr;     //receive shift register
reg run;
reg [31:0] cycleCounter;

//parameter bitTime = 860; // 8600ns / 10.0 ns.  was 8.0 ns
/*
An rs232 receiver for 115,200 bps, 8 data bits.  Holds one character, which must be read
before the following character arrives.

Initially run = bitCounter = sr == 0.  When RxD falls, bitCount increments.  If RxD is still
0 at midBit, run is set.  This keeps bitCount advancing through 0..BitTime ulntil run falls,
which occurs when the start bit shifts into sr[0].  The shift register samples every midBit.
The character is ~sr[8:1].  When the system reads the character (readSR = 1), the shift register is cleared.
*/

  assign rq = ~a3 ? {7'b0, 7'd100, EtherCore, whichCore, txReady, sr[0], ~sr[8:1]} : //speed in MHz = 100
                    cycleCounter;
  
  assign readSR =  selRS232 & ~read & wq[8];
  assign writeTx = selRS232 & ~read & wq[9];
  assign done = selRS232;
  assign wrq =  selRS232 & read;
  assign rwq =  selRS232 & ~read;
  
  assign txReady = bitCnt == 0;
 

  assign runCounter = ~RxD | run;
  assign midBit = bitCounter == bitTime/2;  
  
  always @(posedge clock)  //the bitCounter
    if(runCounter & (bitCounter < bitTime)) bitCounter <= bitCounter + 1;
    else bitCounter <= 0;
    
  always @(posedge clock) // the run flipflop
    if(reset) run <= 0;
    else if(~RxD & midBit & ~run) run <= 1;
    else if(readSR) run <= 0;
    
  always @(posedge clock)
    if(reset) sr <= 0;
    else if(midBit & ~sr[0]) begin
      sr[8:0] <= sr[9:1]; //right shift
      sr[9] <= ~RxD; //sample the input
    end
    else if(readSR) sr <= 0;
  
 
  /* The transmitter.  A 10 bit shift register, 
  a counter to count one bit time, and a 10 bit counter to send 10 bits (start, 8 data, stop)
  */
  always @(posedge clock)
    if (reset) bitCnt <= 0;	// cjt
    else if (writeTx) bitCnt <= 12;
    else if ((bitCnt > 0) & (txCounter == bitTime)) bitCnt <= bitCnt - 1;
	 
    always @(posedge clock)
	   if (writeTx | (txCounter == bitTime)) txCounter <= 0;
	   else txCounter <= txCounter + 1;
		
    always @(posedge clock)
	   if (writeTx) txData <= {~wq[7:0], 1'b1};
      else if (txCounter == bitTime) begin
        txData[8] <= 1'b0;
        txData[7:0] <= txData[8:1]; ///right shift
      end

   assign TxD = ~txData[0];
   assign txReady = (bitCnt == 0);

  // The cycle counter.  Just counts clock cyles since startup.
  always @(posedge clock) cycleCounter <= reset ? 0 : cycleCounter + 1;

endmodule
