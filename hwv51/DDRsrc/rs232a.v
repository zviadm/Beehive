`timescale 1ns / 1ps
module rs232a(

input clock,
input reset,

//The RS232 implements a 115,200 bps, 8 data bits, one stop bit UART.
//Reading from the receiver returns the character and charReady.
//If charReady is true when the receiver is read, it is cleared.

input readRX,
output [7:0] RXchar, //the character if charReady else undefined
output charReady,    //skip condition

//Reading from the transmitter returns TXempty (a skip condition)
//Writing to the the transmitter clears TXempty and transmits TXchar.

output TXempty,     //the transmitter is ready for a character
input writeTX,      //TXchar contains the character to transmit.
input [7:0] TXchar,

input RxD,
output TxD

);

wire runCounter;
wire midBit;
reg [10:0] bitCounter;
reg [10:0] txCounter; //one bit time
reg [3:0] bitCnt; //transmit bit counter
reg [8:0] txData; //transmit shift register
reg [9:0] sr;     //receive shift register
reg run;

parameter RxBitTime = 430; //8600ns / 20.0 ns
//Usually, RxBitTime and TxBitTime are the same.  For debugging, they can be different.
parameter TxBitTime = 430;

/*
Initially run = bitCounter = sr = 0.  When RxD falls, bitCount increments.  If RxD is still
0 at midBit, run is set.  This keeps bitCount advancing through 0..BitTime ulntil run falls,
which occurs when the start bit shifts into sr[0].  The shift register samples every midBit.
The character is ~sr[8:1].  When the system reads the character, 
if sr[0] = 1, the shift register is cleared.
*/

  assign RXchar = ~sr[8:1];
  assign charReady = sr[0];
  assign runCounter = ~RxD | run;
  assign midBit = bitCounter == RxBitTime/2;  
  
  always @(posedge clock)  //the bitCounter
    if(runCounter & (bitCounter < RxBitTime)) bitCounter <= bitCounter + 1;
    else bitCounter <= 0;
    
  always @(posedge clock) // the run flipflop
    if(reset) run <= 0;
    else if(~RxD & midBit & ~run) run <= 1;
    else if(readRX & sr[0]) run <= 0;
    
  always @(posedge clock)
    if(reset | (readRX & sr[0])) sr <= 0;
    else if(midBit & ~sr[0]) begin
      sr[8:0] <= sr[9:1]; //right shift
      sr[9] <= ~RxD; //sample the input
    end
 
 
  /* The transmitter.  A 10 bit shift register, 
  a counter to count one bit time, and a 4 bit counter to send 10 bits (start, 8 data, stop)
  */

  assign TXempty = (bitCnt == 0);
  assign TxD = ~txData[0];

  always @(posedge clock)
    if(reset) bitCnt <= 0;
	 else begin
      if (writeTX) bitCnt <= 12;
	   else if((bitCnt != 0) & (txCounter == TxBitTime)) bitCnt <= bitCnt - 1;
	 end
	 
    always @(posedge clock)
	   if (writeTX | (txCounter == TxBitTime)) txCounter <= 0;
	   else txCounter <= txCounter + 1;
		
    always @(posedge clock)
	   if(reset) txData <= 0;
		else begin
	     if (writeTX) txData <= {~TXchar, 1'b1};
        else if (txCounter == TxBitTime) begin
          txData[8] <= 1'b0;
          txData[7:0] <= txData[8:1]; ///right shift
        end
	  end

 endmodule
