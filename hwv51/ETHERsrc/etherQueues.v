`timescale 1ns / 1ps
module etherQueues(
//signals common to all local I/O devices:
  input clock, //125 MHz clock
  input reset,
  input [30:3] aq, //the CPU address queue output.
  input read,      //request in AQ is a read
  input [27:0] wq, //the CPU write queue output
  output rwq,      //read the write queue
  output [12:0] rqEQ, //the CPU read queue inpput -- only 13 bits used.
  output wrq,      //write the read queue
  output done,     //operation is finished. Read the AQ
  input selEQ,

  input RXheaderCountNonzero,
  output [27:0] RXdmaAddr,
  input readRXdmaAddr,
  output RXdmaEmpty,

  input [12:0] RXframeLength,  //11 bit frame length (bytes), plus goodFrame, badFrame
  input writeFrameLength,

  output [27:0] TXdmaAddr,
  input readTXdmaAddr,
  output TXdmaEmpty,

  output [26:0] TXdmaLength,
  input readTXdmaLength,
  output reg headerRead
 );


/* This module is local I/O device 1 on the SimpleRISC.

It has four FIFOs:

1) A receive DMA address fifo, which has the (28-bit) address into which a
received frame should be transferred.  This fifo is loaded from wq by an
I/O write with aq[3] = 1.

2) A receive DMA completion fifo which returns the total number of bytes
in a received frame and the good/bad status of the frame, or zero if
the completion fifo is empty.  It is read by an I/O read with aq[3] = 0.
 
3) A transmit DMA address fifo, which contains the (28-bit) address
from which a transmitted frame should be fetched.  It is loaded from
wq by an I/O write with aq[3] = 0.

4) A transmit DMA length fifo, which contains the TX DMbase (8),TX header length (5), source core
number (4)  and the payload length(11) of a frame to be transmited.  It is loaded from aq[31:4] by an
I/O write with aq[3] = 0.

This unit also has a three bit status field which can be read by
an I/O read with aq[3] = 1.  The field contains:

a) The RXheaderCountNonzero bit in bit zero. The
controller polls this to determine whether the receiver
has deposited the header of an incoming frame in its data
memory.

b) The transmit DMA address fifo almostFull flag in
bit 1.  The transmitter portion of the control program polls
this flag to avoid overruning the transmit DMA queues.

c) The receive frameLengthEmpty flag in bit 2.  The controller
program should only read the frameLength fifo if it is nonempty,
or the queue will underflow (*bad*).


*/
wire writeRdmaAddrQ;
wire writeTdmaAddrQ;
wire readRXframeLength;
wire frameLengthEmpty;
wire [12:0] readLength; //goes to the processor's rq
(* KEEP = "TRUE" *) wire TXalmostFull;
reg [5:0] txCount;  //number of occupied elements in the tdmaLengthQ
wire RdmaAddrAlmostFull;
reg [5:0] RdmaCount;

//------------------End of Declarations-----------------------

assign writeRdmaAddrQ = selEQ & ~read & aq[3];

always @(posedge clock)
  if (reset) headerRead <= 0;
  else if (writeRdmaAddrQ) headerRead <= ~headerRead;

assign writeTdmaAddrQ = selEQ & ~read & ~aq[3];

assign readRXframeLength = selEQ & read & ~aq[3];

assign done = selEQ; //all operations take one cycle.

assign wrq = selEQ & read;

assign rwq = selEQ & ~read;


//We only report RXheaderCountNonzero if there is room in the address queue.
 
assign rqEQ = aq[3] ?  {10'b0, frameLengthEmpty, TXalmostFull,
  (~RdmaAddrAlmostFull & RXheaderCountNonzero)} : readLength;

always @(posedge clock)
  if(reset) txCount <= 0;
  else if(readTXdmaLength & ~writeTdmaAddrQ) txCount <= txCount - 1;
  else if(~readTXdmaLength & writeTdmaAddrQ) txCount <= txCount + 1;
  
assign TXalmostFull = (txCount[5] & txCount[4]);

always @(posedge clock)
  if(reset) RdmaCount <= 0;
  else if(readRXdmaAddr & ~writeRdmaAddrQ) RdmaCount <= RdmaCount - 1;
  else if(~readRXdmaAddr & writeRdmaAddrQ) RdmaCount <= RdmaCount + 1;
  
assign RdmaAddrAlmostFull = (RdmaCount[5] & RdmaCount[4]);
  
queueN #(.width(28)) rdmaAddrQ(
  .clk(clock),
  .din(wq[27:0]),
  .rd_en(readRXdmaAddr),
  .rst(reset),
  .wr_en(writeRdmaAddrQ),
  .dout(RXdmaAddr),
  .empty(RXdmaEmpty),
  .full()
  );

queueN #(.width(28)) tdmaAddrQ(
  .clk(clock),
  .din(wq[27:0]),
  .rd_en(readTXdmaAddr),
  .rst(reset),
  .wr_en(writeTdmaAddrQ),
  .dout(TXdmaAddr),
  .empty(TXdmaEmpty),
  .full()
  );
  
queueNnef #(.width(27)) tdmaLengthQ(
  .clk(clock),
  .din(aq[30:4]), //DMbase (8), header length (5), source core (4), payload length (11)
  .rd_en(readTXdmaLength),
  .rst(reset),
  .wr_en(writeTdmaAddrQ),  //written from AQ while the address queue is written from wq.
  .dout(TXdmaLength)
  );

queueN #(.width(13)) rxFrameLengthQ(
  .clk(clock),
  .din(RXframeLength),
  .rd_en(readRXframeLength),
  .rst(reset),
  .wr_en(writeFrameLength),
  .dout(readLength),
  .empty(frameLengthEmpty),
  .full()
  );  
endmodule
