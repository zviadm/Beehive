`timescale 1ns / 1ps

module DebugUnit(
 input clock,
 input reset,
 input [31:0] link,
 input [30:0] PC,
 input [3:0] whichCore,
 input j7valid,  //enable operations
 input [2:0]opcode,  //from rb[2:0]
 
 input rqe,       //read queue is empty
 input ctrlValid, //control message information from the Messenger
 input [3:0] ctrlSrc,
 input [3:0] ctrlType,
 
 output loadLink,
 output [31:0] linkValue,
 output zeroPCsetNullify,
 output emptyAWqueues,
 input stopOK
    );

 reg [30:0] savedPC;
 reg [31:0] savedLink;
 reg running;
 reg stopSafely;
 wire doKill;  //stop, empty AQ/WQ.
 wire doStop;  //stop safely
 wire doStart;
 wire doBreak;
 
 parameter nop = 0;  //opcode values
 parameter sendSaveArea = 1;
 parameter sendSavedPC = 2;
 parameter sendSavedLink = 3;
 parameter sendRQempty = 4;
 parameter sendRunning = 5;
 parameter isBreakpoint = 6;
 
//---------------------End of declarations--------------------
 assign doKill  =  running & ctrlValid & (ctrlSrc == 1) & (ctrlType == 2); //got a kill message
 assign doStop  =  running & ctrlValid & (ctrlSrc == 1) & (ctrlType == 1); //got a stop message
 assign doStart =  ctrlValid & (ctrlSrc == 1) & (ctrlType == 0); //got a start message
 assign doBreak = j7valid & (opcode == isBreakpoint);
 
 always@(posedge clock) if(reset | (stopSafely & stopOK) | doKill) stopSafely <= 0;
   else if(doStop) stopSafely <= 1;
 
 always @(posedge clock) if(reset | doBreak | doKill | (stopSafely & stopOK))
   running <= 0;
 else if(doStart)
   running <= 1;

 always @(posedge clock) if (doBreak | (stopSafely & stopOK) | doKill) begin
   savedLink <= link;
   savedPC <= PC;
 end
 
 assign zeroPCsetNullify = (stopSafely & stopOK) | doBreak | doKill;
 assign emptyAWqueues = doKill;

 assign loadLink = j7valid &
    (
	  (opcode == sendSaveArea) |
	  (opcode == sendSavedPC) |
	  (opcode == sendSavedLink) |
	  (opcode == sendRQempty) |
	  (opcode == sendRunning)
	 );
 assign linkValue = 
   (j7valid & (opcode == sendSaveArea))? {17'b0, ({2'b0, whichCore} + 6'b100000), 9'b0}:
   (j7valid & (opcode == sendSavedPC))? {1'b0, savedPC}:
   (j7valid & (opcode == sendSavedLink))? savedLink :
	(j7valid & (opcode == sendRQempty))? {31'b0, ~rqe} :
	(j7valid & (opcode == sendRunning))? {31'b0, running} :
	0;
endmodule
