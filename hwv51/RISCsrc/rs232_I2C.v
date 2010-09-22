`timescale 1ns / 1ps

// © Copyright Microsoft Corporation, 2008

module rs232_I2C(
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
  input [6:3] a,  //a[5] is SCL, a[4] is SDA for the I2C, a[4:3] select the sub-device: 0 => RS232, 1=> cycleCounter, 2 => I2C
  input SDAin,
  output reg SDAx,
  output reg SCLx,  
  input RxD, //received serial data
  output TxD, //transmit serial data
  input [3:0] whichCore    //returned as bits 13:10 of rq 
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

parameter bitTime = 860; // 8600ns / 10.0 ns.  was 8.0 ns
/*
An rs232 receiver for 115,200 bps, 8 data bits.  Holds one character, which must be read
before the following character arrives.

Initially run = bitCounter = sr == 0.  When RxD falls, bitCount increments.  If RxD is still
0 at midBit, run is set.  This keeps bitCount advancing through 0..BitTime ulntil run falls,
which occurs when the start bit shifts into sr[0].  The shift register samples every midBit.
The character is ~sr[8:1].  When the system reads the character (readSR = 1), the shift register is cleared.
*/

  assign rq = (a[4:3] == 2'b00) ? {18'b0, whichCore, txReady, sr[0], ~sr[8:1]} :
              (a[4:3] == 2'b01) ? cycleCounter :
				  {31'b0, SDAin};
  
  assign readSR =  selRS232 & (a[4:3] == 2'b00) & ~read & wq[8];  //the RS232 is selected
  assign writeTx = selRS232 & (a[4:3] == 2'b00) & ~read & wq[9];
  assign done = selRS232; //all operations complete in 1 cycle
  assign wrq =  selRS232 &  read;  
  assign rwq =  selRS232 & (a[4:3] != 2'b10) & ~read;  //I2C takes data from AQ, not WQ, so it doesn't read WQ
  
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
    if (writeTx) bitCnt <= 12;
	 else if((bitCnt > 0) & (txCounter == bitTime)) bitCnt <= bitCnt - 1;
	 
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
  always @(posedge clock) cycleCounter <=  cycleCounter + 1;
  
  //The SDA and SCL I2C signals. The I2C takes data from AQ, not WQ
  always @(posedge clock)
    if(reset) begin
	   SDAx <= 0;
		SCLx <= 0;
	 end else if(selRS232 & ~read & (a[4:3] == 2'b10)) begin
	   SCLx <= a[5];
      SDAx <= a[6];
    end		
  
 endmodule
