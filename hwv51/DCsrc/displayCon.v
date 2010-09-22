`timescale 1ns / 1ps

module displayCon(
  input clock,  
  input clock90,
//  input Ph0,
  input reset,
  
 // output[7:0] LED,

//Outputs to the Chrontel chip:
  output [11:0] DVIdata,
  output DVIclkP,
  output DVIclkN,
  output DVIhsync,
  output DVIvsync,
  output DVIde, //data enable
  output DVIresetB, //low true DVIreset
//DVI I2C
//  inout DVIscl,  //clock
//  inout DVIsda,   //data

  input [95:0] RD, //memory data: Four pixels, each of 24 bits
  input RDready,
  output reg [25:0] RA, //the read (cache line) address
  output readReq,
  input readAck,
  input [25:0] displayAddress,
  output verticalFP  
    );
/*
This module is a display controller for the Beehive.  It consists of two
primary subsections:  (1) A Timing Generator to generate the timing signals
needed by the Chrontel CH7301C chip that drives the DVI connector, and (c) a DMA unit that fetches
the display data from memory.

The Chrontel I2C setup is now done by the RISC in the block copier.

Since the display needs data at a rate that exceeds the 400MB/sec. capacity
of the ring, it uses a separate path for read data from memory.  This path
is supplied by a "back door" port into the memMux module.

The controller displays a single frame buffer from a fixed location in memory
(currently at (cache line) 0x1000000).  The controller only supports
24-bit color.  The 8-bit pixels are packed into words thusly: 0,r,g,b.
Scan lines (parameter tHdD) must be a multiple of 8 words in length.

The controller fetches cache lines starting at 0x1000000 during each
frame, and buffers the data in a fifo.  at the end of the frame, the
address counter and the fifo are reset. The fifo contains
256 cache lines.

*/

reg [1:0] vState;         //vertical timing generator FSM.
reg [1:0] hState;         //horizantal timing generator FSM.
reg [12:0] hCnt;          //horizontal timing counter
reg [12:0] vCnt;          //vertical timing counter;
wire hEnd;                //end of horizontal front porch. Change vState.
(* KEEP = "TRUE" *) wire[7:0] r;          //pixel data
(* KEEP = "TRUE" *) wire[7:0] g;          //pixel data
(* KEEP = "TRUE" *) wire[7:0] b;          //pixel data

parameter tVfp = 0;      //vertical states:  front porch duration
parameter tVw  = 1;      //vertical sync pulse duration
parameter tVbp = 2;      //vertical back porch duration
parameter tVd  = 3;      //vertical display period

parameter tHfp = 0;      //horizontal states: horizontal front porch
parameter tHw  = 1;      //horizontal sync pulse
parameter tHbp = 2;      //horizontal back porch
parameter tHd  = 3;      //horizontal display

//horizontal timing parameters
parameter tHfpD =   64;
parameter tHwD  =   128;
parameter tHbpD =   192;
parameter tHdD  =  1280;

//vertical timing parameters
parameter tVfpD =    3;
parameter tVwD  =    7;
parameter tVbpD =   20;
parameter tVdD  =  960;

wire[11:0] first, second;
(* KEEP = "TRUE" *) wire stopDMA;
wire lastPixel;
reg pCnt;
(* KEEP = "TRUE" *) wire fifoReset;
reg [9:0] startWait;

//-------------End of declarations-------------------------

assign verticalFP = (vState == tVfp);

//wait 1024 cycles after lastPixel to allow any reads that were in flight
//to be discarded before issuing the first request of the new
//frame.
always@(posedge clock) if(lastPixel) startWait <= 10'b1111111111;
  else if(startWait != 0) startWait <= startWait - 1;
  
assign readReq = ~stopDMA & (RA != 0) & (startWait == 0);

//always @(posedge clock) if(reset) lastPixel <= 0;
//  else lastPixel <= (hState == tHd) & (hCnt == 1) & (vState == tVd) & (vCnt == 1);
assign lastPixel = (hState == tHd) & (hCnt == 1) & (vState == tVd) & (vCnt == 1);

assign fifoReset = reset | (startWait != 0);

always @(posedge clock) if (reset) pCnt <= 0;
 else if(RDready) pCnt <= ~pCnt;

always @(posedge clock) if (lastPixel) RA <= displayAddress;
 else if(readAck) RA <= RA + 1;
 
assign first =  DVIde ? {g[3:0], b[7:0]} : 12'b0;
assign second = DVIde ? {r[7:0], g[7:4]} : 12'b0;

genvar i; //the ODDRs for the data
 generate
  for(i = 0; i < 12; i = i + 1)
  begin: dataPin
 
 ODDR #(.SRTYPE("SYNC"),.DDR_CLK_EDGE("SAME_EDGE"))  oddr_clk (
    .Q (DVIdata[i]),
    .C (clock),
    .CE (1'b1),
    .D1 (first[i]),
    .D2 (second[i]),
    .R (1'b0),
    .S (1'b0)
  ); 
  end
 endgenerate

wire [23:0] outWord;
reg [1:0] outCount;
wire [95:0] fifoDout;
wire readFifo;
(* KEEP = "TRUE" *) wire fifoEmpty;

assign outWord =
  outCount == 0 ? fifoDout[23:0] :
  outCount == 1 ? fifoDout[47:24] :
  outCount == 2 ? fifoDout[71:48] :
  fifoDout[95:72];

assign r = outWord[23:16];
assign g = outWord[15:8];
assign b = outWord[7:0];

always@(posedge clock)
    if(reset | fifoReset | (outCount == 3)) outCount <= 0;
    else if(DVIde) outCount <= outCount + 1;

assign readFifo = outCount == 3;
	 
frameFifo buffer (
	.clk(clock),
	.rst(fifoReset),
	.din(RD), // Bus [95 : 0] 
	.wr_en(RDready & ~fifoReset),
	.rd_en(readFifo & ~fifoReset),
	.dout(fifoDout), // Bus [95 : 0] 
	.full(),
	.empty(fifoEmpty),
	.prog_full(stopDMA));

assign DVIresetB = ~reset;
assign hEnd = (hState == tHfp) & (hCnt == 1);
assign DVIhsync = (hState == tHw); 
assign DVIvsync = (vState == tVw); 
assign DVIde =  (hState == tHd) & (vState == tVd); 

always @(posedge clock) if (reset) begin
  hCnt <= tHfpD;
  hState <= tHfp;
 end
 
 else case(hState)
   tHfp: begin
	  hCnt <= hCnt -1;
	  if(hCnt == 1) begin
	    hCnt <= tHwD;
		 hState <= tHw;
	  end
	end
	  
   tHw: begin
	  hCnt <= hCnt - 1;
	  if(hCnt == 1) begin
	    hCnt <= tHbpD;
		 hState <= tHbp;
	  end
	end
	  
	tHbp: begin
	  hCnt <= hCnt - 1;
	  if(hCnt == 1) begin
	    hCnt <= tHdD;
		 hState <= tHd;
	  end
	end
	
	tHd: begin 
	  hCnt <= hCnt - 1;
	  if(hCnt == 1) begin
	    hCnt <= tHfpD;
		 hState <= tHfp;
     end
	end
   endcase

always @(posedge clock) if (reset) begin
  vCnt <= tVfpD;
  vState <= tVfp;
 end
 
 else case(vState)
   tVfp: if(hEnd) begin
	  vCnt <= vCnt -1;
	  if(vCnt == 1) begin
	    vCnt <= tVwD;
		 vState <= tVw;
	  end
	end
	  
   tVw: if(hEnd) begin
	  vCnt <= vCnt - 1;
	  if(vCnt == 1) begin
	    vCnt <= tVbpD;
		 vState <= tVbp;
	  end
	end
	  
	tVbp: if(hEnd) begin
	  vCnt <= vCnt - 1;
	  if(vCnt == 1) begin
	    vCnt <= tVdD;
		 vState <= tVd;
	  end
	end
	
	tVd: if(hEnd) begin 
	  vCnt <= vCnt - 1;
	  if(vCnt == 1) begin
	    vCnt <= tVfpD;
		 vState <= tVfp;
     end
	end
   endcase

 
//The DDR clock to the Chrontel

ODDR #(.SRTYPE("SYNC"),.DDR_CLK_EDGE("SAME_EDGE"))  ddr_clkA (
    .Q (DVIclkP),
    .C (clock90),
    .CE (1'b1),
    .D1 (1'b1),
    .D2 (1'b0),
    .R (1'b0),
    .S (1'b0)
  ); 

ODDR #(.SRTYPE("SYNC"),.DDR_CLK_EDGE("SAME_EDGE"))  ddr_clkB (
    .Q (DVIclkN),
    .C (clock90),
    .CE (1'b1),
    .D1 (1'b0),
    .D2 (1'b1),
    .R (1'b0),
    .S (1'b0)
  ); 

endmodule
