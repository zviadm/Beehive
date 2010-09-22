`timescale 1ns / 1ps
module SimpleDataMemory(

/* This is the 1K x 32 data memory for the Ethernet CPU.  It
doesn't interact with the ring, but can be loaded from the
receive section of the design with the first 4 words of
the arriving Ethernet frame.

The transmit header is taken from an independent read port,
which means we need two block rams.

*/
//signals common to all local I/O devices:
  input clock, //125 MHz clock
  input [9:0] aq, //the CPU address queue output.
  input read,      //request in AQ is a read
  input [31:0] wq, //the CPU write queue output
  output rwq,      //read the write queue
  output [31:0] rqDCache, //the CPU read queue inpput
  output wrq,      //write the read queue
  output done,     //operation is finished. Read the AQ, read WQ if operation was write
  input selDCache,
  
//Data, Address, and WriteStrobe from the receiver block
  input [9:0] receiverAddress,
  input [31:0] receiverData,
  input receiverWrite,
  input receiverClock,
  
  input[9:0] DMaddr,
  output[31:0] DMdata,
  input readClock

 );
	 
 wire writeDdata;
 reg select;

	
dpbram32 dataCache1 (
	.rda(rqDCache),         //the input of the read queue
	.wda(wq),         //the output of the write queue 
	.aa(aq[9:0]),     //address with the low bits of the address queue 
	.wea(writeDdata),    //write enable 
	.ena(1'b1),
	.clka(clock),
	.rdb(),                  //the second port is write-only
	.wdb(receiverData),      //the data from the receiver 
	.ab(receiverAddress),    //receiver address 
	.web(receiverWrite),     //write enable 
	.enb(1'b1),
	.clkb(receiverClock)
	);

dpbram32 dataCache2 (
	.rda(),           //unused
	.wda(wq),         //the output of the write queue 
	.aa(aq[9:0]),     //address with the low bits of the address queue 
	.wea(writeDdata),    //write enable 
	.ena(1'b1),
	.clka(clock),
	.rdb(DMdata),                  //the second port is read-only
	.wdb(32'b0),
	.ab(DMaddr),    //receiver address 
	.web(1'b0),     //write enable 
	.enb(1'b1),
	.clkb(readClock)
	);

always @(posedge clock) select <= selDCache & ~done;
							
assign done = select;
assign wrq = done & read;
assign rwq = done & ~read;
assign writeDdata = select & ~read;


endmodule
