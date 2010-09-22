`timescale 1ns / 1ps
module copierDataMemory(

// This is the 64W x 32 data memory for the block copier.

//signals common to all local I/O devices:
  input clock,
  input [5:0] aq, //the CPU address queue output.
  input read,      //request in AQ is a read
  input [31:0] wq, //the CPU write queue output
  output rwq,      //read the write queue
  output [31:0] rqDCache, //the CPU read queue inpput
  output wrq,      //write the read queue
  output done,     //operation is finished. Read the AQ, read WQ if operation was write
  input selDCache
 );
	 
 wire writeDdata;
 reg select;

//Instantiate the data memory. A simple single-port RAM.
ramy dm (
	.a(aq),  
	.d(wq), 
	.clk(clock),
	.we(writeDdata),
	.spo(rqDCache)); 
/*	
dpbram32 dataCache (
	.rda(rqDCache),         //the input of the read queue
	.wda(wq),         //the output of the write queue 
	.aa(aq[9:0]),     //address with the low bits of the address queue 
	.wea(writeDdata),    //write enable 
	.ena(1'b1),
	.clka(clock),
	.rdb(),                  //the second port is not used
	.wdb(32'b0), 
	.ab(10'b0),  
	.web(1'b0), 
	.enb(1'b0),
	.clkb(1'b0)
	);
*/

always @(posedge clock) select <= selDCache & ~done;
							
assign done = select;
assign wrq = done & read;
assign rwq = done & ~read;
assign writeDdata = select & ~read;

endmodule
