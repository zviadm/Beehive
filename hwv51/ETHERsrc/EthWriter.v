`timescale 1ns / 1ps
module EthWriter(
input CLK,
input reset,

input clientRXclock,

input [7:0] RXdata,  //data from MAC
input RXdataValid,
input RXgoodFrame,
input RXbadFrame,

output reg [9:0] receiverAddress,  //address, data, and strobe to CPU data memory
output [31:0] receiverData,
output receiverWrite,

output headerCountNonZero,
input headerRead,  //CPU has read the header. This is in the CLK domain

output [32:0] memoryData,
output dataReady,
input readWord
);

/* This module takes data from the MAC, buffers it
in a 1KW x 32 FIFO.  The first 16 bytes of the packet
are also placed in the Data memory of the SimpleRISC.
The top quarter of the(4KB) data memory is reserved for
this header data and treated as a ring buffer.  As each
header is transferred, an up-down counter indicating the
number of headers in the buffer is incremented.  The
CPU polls this counter, and when it is nonzero, the CPU
processes the header to determine where to deposit the
packet in main memory, and sets up the DMA write engine.
The write engine extracts data from the buffer, packages
it into 32-byte blocks, and writes it to main memory
via the ring.

Once the MAC begins to deliver a frame, asserts RXdataValid and delivers
one byte per clock until the frame ends, at which point it drops
RXdataValid.  A short time later, the MAC asserts RXgoodFrame
or RXbadFrame for one cycle.  The logic loads one byte of the
bytes register on each byte, and the bytes registers are sent to the writeFIFO on the clock
following the write of the fourth byte.

When RXdataValid drops, if the bytes register is not full, the FIFO is still written
with the partial word. When RXgoodFrame or RXbadFrame asserts, a
final word is written to the FIFO with bit 32 set.  This word
contains {19'b0, byteCount[10:0], RXgoodFrame, RXbadFrame}, which
allows the downstream logic to determine the length of the frame in
bytes.  byteCount is cleared at the assertion of
RXgoodFrame or RXbadFrame in preparation for the next frame's arrival.

The headerCount represents the number of headers that have been
delivered to the CPU data memory but not processed by the CPU. This counter
is incremented as the last word of the header is delivered, and at
the end of every frame, if it is equal to 32 the headerMaxed bit is
set.  If headerMaxed is set, frames are silently discarded until it
is cleared.  This should, of course, never happen.

*/

wire writeFifo;
//wire fifoFull;
wire [32:0] fifoInData;
reg [7:0] bytes[0:3]; //accumulates a full word for writing to the fifo and CPU data memory.
reg [10:0] byteCount;  //bytes delivered to the fifo. Max frame is ~1500 bytes
reg stageFull;
reg [4:0] headerCount; //count of headers waiting for the CPU to process
wire incHeaderCnt;
wire decHeaderCnt;
reg headerMaxed;         //headerCount at max. Silently discard frames
//reg [2:0] wordsSent;     //4-byte words sent to the CPU data memory.
reg hr1, hr2, hr3;
reg RXdvDly;
reg [3:0] headerBytes;    //counts 0..14d
wire headerDone;
//----------------End of declarations-------------

always @(posedge clientRXclock)
  if(reset | RXgoodFrame | RXbadFrame) headerBytes <= 0;
  else if(~headerDone & RXdataValid) headerBytes <= headerBytes + 1;  //sticks at 15
  
assign headerDone = (headerBytes == 15);

//We must get headerRead (which toggles when the DMA address is loaded)
//into the clientRXclock domain, and 
//make it one cycle in length
always @(posedge clientRXclock) begin
  hr1 <= headerRead;
  hr2 <= hr1;
  hr3 <= hr2;
end

//The header counter:
assign decHeaderCnt = hr2 ^ hr3;
assign incHeaderCnt = ~headerMaxed & RXdataValid & (headerBytes == 13);

always @(posedge clientRXclock)
  if(reset) headerCount <= 0;
  else if (incHeaderCnt & ~decHeaderCnt) headerCount <= headerCount + 1;
  else if (~incHeaderCnt & decHeaderCnt) headerCount <= headerCount - 1;
  
assign headerCountNonZero = (headerCount != 0); 

always @(posedge clientRXclock)
  if(reset) headerMaxed <= 0; 
  else if(RXgoodFrame | RXbadFrame) headerMaxed <= (headerCount == 31);

//The following logic is concerned with getting data from the MAC to the writeFIFO:

always @(posedge clientRXclock)
  if(reset | RXgoodFrame | RXbadFrame | (headerBytes == 13)) byteCount <= 0; 
  else if(~headerMaxed & RXdataValid) byteCount <= byteCount + 1;

always @(posedge clientRXclock) if (RXdataValid & ~headerMaxed) bytes[byteCount[1:0]] <= RXdata;

always @(posedge clientRXclock) if(reset | RXgoodFrame | RXbadFrame) stageFull <= 0;
  else if (RXdataValid & ~headerMaxed) stageFull <= (byteCount[1:0] == 3);

always @(posedge clientRXclock) RXdvDly <= RXdataValid;

//transfer from bytes to the writeFifo.
assign writeFifo = ~headerMaxed & ((stageFull & RXdataValid & headerDone ) | (~RXdataValid & RXdvDly) | RXgoodFrame | RXbadFrame);

assign fifoInData = (RXgoodFrame | RXbadFrame) ?  {1'b1, 19'b0, byteCount, RXgoodFrame, RXbadFrame} :
      {1'b0, bytes[3], bytes[2], bytes[1], bytes[0]};

//The logic to transfer from bytes into the CPU data memory:
 
assign receiverData = {bytes[0], bytes[1], bytes[2], bytes[3]};

assign receiverWrite = ~headerMaxed & ((stageFull & ~headerDone) | (headerBytes == 14));  //write the DM

always @(posedge clientRXclock)  //data memory address
  if(reset | (receiverWrite &  (& receiverAddress))) receiverAddress <= 10'd768;
  else if(receiverWrite) receiverAddress <= receiverAddress + 1;  

wire writeFIFOempty;
assign dataReady = ~writeFIFOempty;
 
EthFIFO writeFIFO (
	.din(fifoInData), // Bus [32 : 0] 
	.rd_clk(CLK),
	.rd_en(readWord),
	.rst(reset),
	.wr_clk(clientRXclock),
	.wr_en(writeFifo),
	.dout(memoryData), // Bus [32 : 0] 
	.empty(writeFIFOempty),
	.full());

endmodule
