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

When messages for this core arrive,the SlotType is converted from 
Message to Null so that the message will not propagate further.

Messages from the copier (core copyCore) are sent directly to rq.

The messenger sends messages directly from WQ.

When the messenger is selected for reading,
the first message in MQ is copied into RQ. If MQ is 
empty, RQ is loaded with 0.

Messenger supports broadcasts. If a core (1 to nCores) sends message to itself
it will be sent as broadcasts and all other cores (1 to nCores) will receive
the message. Broadcast is taken off from the ring by the sender itself.
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
  input [3:0] copyCore,
  
  //ring signals
  input  [31:0] RingIn,
  input  [3:0] SlotTypeIn,
  input  [3:0] SrcDestIn,
  output [31:0] msgrRingOut,
  output [3:0] msgrSlotTypeOut,
  output [3:0] msgrSrcDestOut,
  output msgrDriveRing,
  output msgrWaiting,
  output ctrlValid,
  output [3:0] ctrlType,
  output [3:0] ctrlSrc
);

  wire         writeMQ;
  wire         MQempty;
  wire         rdMQ;
  wire         firstMessageWord;
  wire [31:0]  MQdata;
  reg [3:0]    state;  //messenger FSM
  reg [5:0]    length; //payload length
  reg [7:0]    burstLength; //length of the train
  reg [5:0]    inLen;  //counts incoming payload length

  parameter idle = 0;  //states
  parameter waitToken = 1;  
  parameter waitN = 2;  //wait for the end of the train
  parameter sendAQ = 3; //send the message header
  parameter sendWQ = 4; //send the message payload
  parameter copyHeader = 5; //from MQ to RQ, and load length
  parameter copyMQ = 6; //from MQ to RQ until length == 1
  parameter copyWait = 7;  //wait for a reply from the copier.
  parameter doCopy = 8;    //one cycle to write the read queue

  parameter Null = 7; //Slot Types
  parameter Token = 1;
  parameter Message = 8;
  parameter Broadcast = 12;

//------------------End of Declarations-----------------------
  wire normalCore = (whichCore > 4'b1) & (whichCore < copyCore - 4'b1);
  assign firstMessageWord = 
    (((SlotTypeIn == Message) & (SrcDestIn == whichCore)) |
     ((SlotTypeIn == Broadcast) & (SrcDestIn != whichCore) & normalCore)) &
    (inLen == 0);
 
  always @(posedge clock) if (reset) inLen <= 0;
    else if (firstMessageWord) inLen <= RingIn[5:0];
    else if (inLen != 0) inLen <= inLen - 1;

  assign msgrWaiting = (state == waitToken);

  //Write the first message word into MQ unless the message length is zero
  //or the source core is copyCore. Write later words (inLen != 0)
  //unless they are copier replies (state == doCopy).  The copier only
  //sends messages with a 1-word payload.  
  assign writeMQ = 
    (firstMessageWord & (RingIn[5:0] != 0) & (RingIn[13:10] != copyCore)) |  
    ((inLen != 0) & (state != doCopy)); 
 
  assign ctrlValid = firstMessageWord & (RingIn[5:0] == 0);
  assign ctrlType  = RingIn[9:6];
  assign ctrlSrc   = RingIn[13:10];
 
  //interactions with the ring
  assign msgrDriveRing = 
    //convert messages sent to me to Null
    ((SlotTypeIn == Message) & (SrcDestIn == whichCore)) |   
    //convert broadcasts sent by me to Null
    ((SlotTypeIn == Broadcast) & (SrcDestIn == whichCore)) |  
    //send the new token
    ((state == waitToken) & (SlotTypeIn == Token)) |  
    //message header & message payload
    (state == sendAQ) | (state == sendWQ);  
    
  assign msgrSrcDestOut =
    ((state == sendAQ) | (state == sendWQ)) ? aq[6:3] :  //the destination core
    SrcDestIn;

  assign msgrSlotTypeOut =
    //replace messages directed to me with Null
    ((SlotTypeIn == Message) & (SrcDestIn == whichCore)) ? Null :  
    //replace messages broadcasted by me with Null
    ((SlotTypeIn == Broadcast) & (SrcDestIn == whichCore)) ? Null :  
    ((state == sendAQ) | (state == sendWQ)) ?
      //send broadcast when dst == src
      (((aq[6:3] == whichCore) & normalCore) ? Broadcast : Message) :
    SlotTypeIn;
    
  assign msgrRingOut = 
    //aq[12:7] is the payload length (may be zero), one one for header
    ((state == waitToken) & (SlotTypeIn == Token)) ? (RingIn + aq[12:7] + 1) :     
    //header: source core(4), type(4), payload length(6)
    (state == sendAQ) ? {18'b0, whichCore, aq[16:7]} : 
    (state == sendWQ) ? wq : //the message payload
    RingIn;

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
    ((state == sendAQ) & (aq[12:7] == 0)) |
    ((state == copyMQ) & (length == 1)) | 
    ((state == sendWQ) & (length == 1) & (aq[6:3] != copyCore)) |  //normal message
    (state == doCopy);   //reply arrived from copier

  assign rwq = (state == sendWQ);

  //the state machine
  always @(posedge clock) begin
    if(reset) state <= idle;
    else case(state)
      idle: if(selMsgr) begin
        if(~read) state <= waitToken;
        else if (~MQempty) state <= copyHeader;
      end
     
      waitToken: if(SlotTypeIn == Token) begin
        if(RingIn[7:0] == 0) state <= sendAQ;
        else begin
          burstLength <= RingIn[7:0];
          state <= waitN;
        end
      end

      waitN: begin  //wait for the end of the train
        burstLength <= burstLength - 1;
        if(burstLength == 1) state <= sendAQ;
      end

      sendAQ: begin
        length <= aq[12:7];  //payload length
        if(aq[12:7] == 0) state <= idle;
        else state <= sendWQ;
      end

      sendWQ: begin  //send data on the ring
        length <= length - 1;
        if(length == 1) begin
          if(aq[6:3] != copyCore) state <= idle;
          else state <= copyWait; //the messenger waits for a reply to messages sent to the copier.
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
        //A message is from the copier if it contains copyCore in the bits 13:10 of the message header.
        //In this case, we insert the 1-word payload (the checksum) directly into RQ.
        if(firstMessageWord & (RingIn[13:10] == copyCore)) state <= doCopy;
    
      doCopy:
        state <= idle;   
    endcase
  end

  //The FIFO for received messages
  FIFO36 #(
    .SIM_MODE("SAFE"), // Simulation: "SAFE" vs. "FAST", 
                       // see "Synthesis and Simulation Design Guide" for details
    .ALMOST_FULL_OFFSET(13'h0080), // Sets almost full threshold
    .ALMOST_EMPTY_OFFSET(13'h0080), // Sets the almost empty threshold
    .DATA_WIDTH(36), // Sets data width to 4, 9, 18 or 36
    .DO_REG(1), // Enable output register (0 or 1)
                // Must be 1 if EN_SYN = "FALSE"
    .EN_SYN(1'b0), // Specifies FIFO as Asynchronous ("FALSE")
                   // or Synchronous ("TRUE")
    .FIRST_WORD_FALL_THROUGH(1'b1) // Sets the FIFO FWFT to "TRUE" or 
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

