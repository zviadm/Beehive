`timescale 1ns / 1ps
/* 
Messenger Module
Created By: Microsoft
Modified By: Zviad Metreveli

The messenger is accessed when the CPU wants to send a message or
poll for a received message.

Messages to this core from cores other than the copier are placed in MQ 
as they arrive on the ring, if they have nonzero length.

When messages of zero length arrive, their source and type are placed
in ctrlSrc and ctrlType, and ctrlValid is asserted.

Messages from the copier (core copyCore) are sent directly to rq.

The messenger sends messages directly from WQ.

When the messenger is selected for reading,
the first message in MQ is copied into RQ. If MQ is 
empty, RQ is loaded with 0.

Messenger supports broadcasts. If a core (2 to nCores) sends message to itself
it will be sent as broadcast and all other cores (2 to nCores) will receive
the message.
*/

module Messenger(
  //signals common to all local I/O devices:
  input clock,
  input reset,
  input [16:3] aq, //msgType [16:13], payload length [12:7], destCore [6:3]
  input read,      //request in AQ is a read
  input [31:0] wq, //the CPU write queue output
  output rwq,      //read the write queue
  output [31:0] rqMsgr, //the CPU read queue input
  output wrq,      //write the read queue
  output done,     //operation is finished. Read the AQ
  input selMsgr,
  input [3:0] whichCore,
  input [3:0] CopyCore,
  
  //ring signals
  input  [31:0] RingIn,
  input  [3:0] SlotTypeIn,
  input  [3:0] SourceIn,
  output [31:0] msgrRingOut,
  output [3:0] msgrSlotTypeOut,
  output [3:0] msgrSourceOut,
  output msgrDriveRing,
  output msgrWantsToken,
  input  msgrAcquireToken,
  
  output ctrlValid,
  output [3:0] ctrlType,
  output [3:0] ctrlSrc
);

  wire         writeMQ;
  wire         MQempty;
  wire         firstMessageWord;
  wire         rdMQ;
  wire [31:0]  MQdata;
  reg [2:0]    state;  //messenger FSM
  reg [5:0]    length; //payload length when copying message from MQ to RQ
  reg [5:0]    inLen;  //counts incoming payload length
  reg          putMessageInMQ;

  localparam idle = 0;  //states
  localparam waitToken = 1;  
  localparam sendWQ = 2; //send the message payload
  localparam copyHeader = 3; //from MQ to RQ, and load length
  localparam copyMQ = 4; //from MQ to RQ until length == 1
  localparam copyWait = 5;  //wait for a reply from the copier.
  localparam doCopy = 6;    //one cycle to write the read queue

//------------------End of Declarations-----------------------
  wire normalCore = (whichCore > 4'b1) & (whichCore < CopyCore - 4'b1);
  assign firstMessageWord = 
    (((SlotTypeIn == `Message) & (RingIn[17:14] == whichCore) & 
      (RingIn[17:14] != RingIn[13:10])) | 
     ((SlotTypeIn == `Message) & (RingIn[17:14] != whichCore) & 
      (RingIn[17:14] == RingIn[13:10]) & normalCore)) & 
    (inLen == 0);
 
  always @(posedge clock) 
    if (reset) begin 
      inLen <= 0;
      putMessageInMQ <= 0;
    end
    else begin
      if (inLen != 0) inLen <= inLen - 1;
      else if (SlotTypeIn == `Message) begin 
        inLen <= RingIn[5:0];
        putMessageInMQ <= firstMessageWord;
      end
    end

  //Write the first message word into MQ unless the message length is zero
  //or the source core is copyCore. Write later words (inLen != 0)
  //unless they are copier replies (state == doCopy).  The copier only
  //sends messages with a 1-word payload.  
  assign writeMQ = 
    (firstMessageWord & (RingIn[5:0] != 0) & (RingIn[13:10] != CopyCore)) |  
    ((inLen != 0) & putMessageInMQ & (state != doCopy)); 
 
  assign ctrlValid = firstMessageWord & (RingIn[5:0] == 0);
  assign ctrlType  = RingIn[9:6];
  assign ctrlSrc   = RingIn[13:10];
   
  //interactions with the ring
  assign msgrWantsToken = (state == waitToken);
  assign msgrDriveRing = 
    //When msgr Acquires Token it sends Header and then Payload
    ((state == waitToken) & (msgrAcquireToken)) | (state == sendWQ);
    
  assign msgrSourceOut = whichCore;
  assign msgrSlotTypeOut = `Message;    
  assign msgrRingOut =     
    ((state == waitToken) & (msgrAcquireToken)) ? 
      // Send Header, 4 bits of dest, source and type, 6 bits of length
      {14'b0, aq[6:3], whichCore, aq[16:7]} :
    (state == sendWQ) ? wq : 32'b0; // Message Payload

  //data between the queues                      
  assign rqMsgr = 
    ((state == idle) & selMsgr & read & MQempty) ? 32'b0 :
    (state == doCopy) ? RingIn :
    MQdata;

  assign wrq = 
    ((state == idle) & selMsgr & read & MQempty) |
    (state == copyHeader) |
    (state == copyMQ) |
    (state == doCopy);

  assign rdMQ = (state == copyHeader) | (state == copyMQ);
 
  assign done = 
    (((state == idle) & selMsgr & read & MQempty)) | 
    ((state == waitToken) & (msgrAcquireToken) & (aq[12:7] == 0)) |
    ((state == sendWQ) & (length == 1) & (aq[6:3] != CopyCore)) |
    ((state == copyMQ) & (length == 1)) | 
    (state == doCopy);   //reply arrived from copier

  assign rwq = (state == sendWQ);

  //the state machine
  always @(posedge clock) begin
    if (reset) state <= idle;
    else case (state)
      idle: if (selMsgr) begin
        if (~read) state <= waitToken;
        else if (~MQempty) state <= copyHeader;
      end
     
      waitToken: if (msgrAcquireToken) begin 
        length <= aq[12:7];  //payload length
        if(aq[12:7] == 0) state <= idle;
        else state <= sendWQ;
      end
      
      sendWQ: begin  //send data on the ring
        length <= length - 1;
        if(length == 1) begin
          if(aq[6:3] != CopyCore) state <= idle;
          else state <= copyWait; //the messenger waits for a reply to 
                                  //messages sent to the copier.
        end
      end

      copyHeader: begin
        state <= copyMQ;
        length <= MQdata[5:0];
      end

      copyMQ: begin  //move from MQ to rq
        length <= length -1;
        if(length == 1) state <= idle;
      end

      copyWait:
        //A message is from the copier if it contains CopyCore in the bits 
        //13:10 of the message header. In this case, we insert the 1-word 
        //payload (the checksum) directly into RQ.
        if(firstMessageWord & (RingIn[13:10] == CopyCore)) state <= doCopy;
    
      doCopy:
        state <= idle;   
    endcase
  end

  //The FIFO for received messages
  FIFO36 #(
    .SIM_MODE("SAFE"), // Simulation: "SAFE" vs. "FAST", 
    .ALMOST_FULL_OFFSET(13'h0080), // Sets almost full threshold
    .ALMOST_EMPTY_OFFSET(13'h0080), // Sets the almost empty threshold
    .DATA_WIDTH(36), // Sets data width to 4, 9, 18 or 36
    .DO_REG(1), // Enable output register (0 or 1)
                // Must be 1 if EN_SYN = "FALSE"
    .EN_SYN("FALSE"), // Specifies FIFO as Asynchronous ("FALSE")
                   // or Synchronous ("TRUE")
    .FIRST_WORD_FALL_THROUGH("TRUE") // Sets the FIFO FWFT to "TRUE" or 
                                     // "FALSE" ("TRUE")
  )

  MQ (
    .ALMOSTEMPTY(), // 1-bit almost empty output flag
    .ALMOSTFULL(), // 1-bit almost full output flag
    .DO(MQdata), // 32-bit data output
    .DOP(), // 4-bit parity data output
    .EMPTY(MQempty), // 1-bit empty output flag
    .FULL(), // 1-bit full output flag
    .RDCOUNT(), // 13-bit read count output
    .RDERR(), // 1-bit read error output
    .WRCOUNT(), // 13-bit write count output
    .WRERR(), // 1-bit write error
    .DI(RingIn), // 32-bit data input
    .DIP(4'b0), // 4-bit parity input
    .RDCLK(clock), // 1-bit read clock input
    .RDEN(rdMQ), // 1-bit read enable input
    .RST(reset), // 1-bit reset input
    .WRCLK(clock), // 1-bit write clock input
    .WREN(writeMQ) // 1-bit write enable input
  );

endmodule

