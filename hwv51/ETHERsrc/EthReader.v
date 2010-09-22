`timescale 1ns / 1ps

module EthReader(
input clock,
input ethTXclock,
input resetIn,

input [31:0] transmitData, //data from dma read engine
input transmitWriteIn,  //write TX fifo (clock domain)
output stopDMA,       //TX fifo is almost full

output [7:0] TXdata,  //transmit data to MAC
output TXdataValid,   //data valid to MAC
input TXack,          //frame accepted by MAC

input [47:4] SMACaddr, //High 44 bits of the source MAC address
output reg [9:0] DMaddr,   //address the DM in the control RISC to get the TX header.
input [31:0] DMdata
);

/* This module receives data from the read DMA engine and formats it
for transmission to the MAC.  To send a frame, the DMA engine enters
a frame length (in bytes) into the fifo, then fills the fifo with the data to be
transmitted.

At the fifo output, an FSM extracts the data and sends it to the MAC 
as a stream of bytes.  To transmit a frame, the FSM first waits until
the entire frame is in the fifo (since once transmission starts, the
fifo must send the entire frame without interruption). 

When the FSM is idle and the fifo becomes nonempty, the system waits until
the entire frame is in the fifo.  This is true when fifoCnt >= byteCnt[10:2] +
(byteCnt[1] | byteCnt[0]).  <Note that the DMA engine fills the fifo with precisely
the number of words needed to hold the frame, which need not end on a word boundary>.

As soon as the frame is in the fifo, the FSM asserts TXdataValid.  Within a few clocks,
the MAC will assert TXack.  At this point the transmitter is committed to sending the
entire frame.  First, the header is sent. The destination MAC address comes from the
CPU DM, the source MAC address is then sent, then the remainder of the header is
sent from DM.  When the header is complete, the payload is sent from the FIFO.

The words in the fifo are multiplexed to a byte stream by the (2-bit) byteSel register,
which is incremented each clock.  As each byte is sent, byteCnt is decremented.  When 
byteCnt == 1, the FSM goes idle and TXdataValid is deasserted.

The fact that the frame must be in the fifo before transmission starts isn't a problem
(except on the first frame of a burst), since the DMA engine will load the fifo with the
next frame's length and data while the first is being sent.  The fifo can hold several frames.

*/

reg [3:0]  SMACaddrLow; //The sending core number.

reg [2:0] xstate;    //transmit FSM
reg [10:0] byteCnt;  //maximum frame is ~1500 bytes.
reg [1:0] byteSel;   //which byte of a word to send to the MAC.
wire [10:0] fifoCnt;   //the number of words in the fifo

parameter idle = 0;     //FSM states
parameter getCnt = 1;   //load byteCnt from fifo, advance fifo
parameter waitData = 2; //wait until frame is in the fifo
parameter sendFirst = 3;     //present first byte, wait for TXack
parameter sendDMACaddr = 4;   //send destination MAC address
parameter sendSMACaddr = 5;   //send source MAC address
parameter sendHeader = 6;     //send remaining header bytes
parameter sendData = 7;       //send the frame payload

wire [31:0] fifoOut;
wire fifoEmpty;
wire readFifo;
reg [8:0] wordsNeeded;

reg [6:0] headerCnt;  //counts down (bytes) during header transmission
reg [2:0] headerSel; //byte selector for header
reg [2:0] SMACcnt;    //selects the source MAC address byte
wire [7:0] hdrData;   //hdrData, SMdata, and paloadData are muxed together to get TXdata
wire [7:0] SMdata;
wire [7:0] payloadData;
reg  [31:0] DMdata1;

reg reset;

//----------------End of declarations-------------

always @(posedge ethTXclock) reset <= resetIn;

always @(posedge ethTXclock) begin
  if(reset) xstate <= idle;
  else case(xstate)  
    idle: begin
	   wordsNeeded <= 0;
		if(~fifoEmpty) xstate <= getCnt;
	 end
	 
	 getCnt: begin
	   wordsNeeded <= fifoOut[10:2] + (fifoOut[1] | fifoOut[0]);
		SMACaddrLow <= fifoOut[14:11]; //source core
		SMACcnt <= 0;
	   xstate <= waitData;
	 end
	 
	 waitData: if((fifoCnt[8:0] >= wordsNeeded) & ~fifoEmpty) xstate <= sendFirst;
	 
	 sendFirst: if(TXack) xstate <= sendDMACaddr; //send first header byte
	 
	 sendDMACaddr: if(headerSel == 5) xstate <= sendSMACaddr;
	 
	 sendSMACaddr: begin  //send six byte source MAC address
	   SMACcnt <= SMACcnt + 1;
      if(SMACcnt == 5) xstate <= sendHeader;
    end

    sendHeader: if(headerCnt == 1) xstate <= sendData;

	 sendData: if(byteCnt == 1) xstate <= idle;
  endcase
end

always @(posedge ethTXclock) if(xstate == idle) headerSel <= 0;
  else if(((xstate == sendFirst) & TXack) |
           (xstate == sendDMACaddr) | 
			  (xstate == sendHeader)) headerSel <= headerSel + 1;

always @(posedge ethTXclock) if (xstate == getCnt) DMaddr <= {fifoOut[26:20], 3'b011};
  else if((headerSel[1:0] == 3) | TXack) DMaddr <= DMaddr + 1;  

always @(posedge ethTXclock) if(xstate == getCnt) headerCnt <= {fifoOut[19:15],2'b0}; //the length fifo has the header length in *words*
  else if (((xstate == sendFirst) & TXack) |
   (xstate == sendDMACaddr) | 
	(xstate == sendHeader)) headerCnt <= headerCnt - 1; 
  
always @(posedge ethTXclock) if(xstate == idle) byteSel <= 0;
  else if(xstate == sendData) byteSel <= byteSel + 1;
  
always @(posedge ethTXclock) if (xstate == getCnt) byteCnt <= fifoOut[10:0];
  else if(xstate == sendData) byteCnt <= byteCnt - 1;
  
always @(posedge ethTXclock) if(((xstate == sendFirst) & ~TXack) | (headerSel[1:0] == 3)) DMdata1 <= DMdata;

assign readFifo = ((byteSel == 3) & (xstate == sendData)) | (byteCnt == 1) | (xstate == getCnt);

assign hdrData = (headerSel[1:0] == 0)? DMdata1[31:24] : //most significant byte first
  (headerSel[1:0] == 1)? DMdata1[23:16] :
  (headerSel[1:0] == 2)? DMdata1[15:8] :
  DMdata1[7:0];

assign SMdata = (SMACcnt == 0)? SMACaddr [47:40] : 
                 (SMACcnt == 1)? SMACaddr [39:32] : 
                 (SMACcnt == 2)? SMACaddr [31:24] : 
                 (SMACcnt == 3)? SMACaddr [23:16] : 
                 (SMACcnt == 4)? SMACaddr [15:8] : 
                 {SMACaddr [7:4], SMACaddrLow[3:0]}; 
						
						
assign payloadData = (byteSel == 0)? fifoOut[7:0] :
                (byteSel == 1)? fifoOut[15:8] :
					 (byteSel == 2)? fifoOut[23:16] :
					 fifoOut[31:24];

assign TXdata =  ((xstate == sendFirst) |(xstate == sendDMACaddr) | (xstate == sendHeader))?  hdrData :
  (xstate == sendSMACaddr)? SMdata :
  payloadData;
  
assign TXdataValid = (xstate == sendFirst) |
 (xstate == sendDMACaddr) |
 (xstate == sendSMACaddr) |
 (xstate == sendHeader) |
 (xstate == sendData);
 
txFifo txFifoX (
	.din(transmitData), // Bus [31 : 0]
   .rd_clk(ethTXclock),	
	.rd_en(readFifo),
	.rst(reset),
	.wr_clk(clock),
	.wr_en(transmitWriteIn),
	.dout(fifoOut), // Bus [31 : 0] 
	.empty(fifoEmpty),
	.full(),
	.prog_full(stopDMA),
	.rd_data_count(fifoCnt));
endmodule
