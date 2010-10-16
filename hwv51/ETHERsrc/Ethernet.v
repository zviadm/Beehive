`timescale 1ns / 1ps
  
/*
  A 1Gbit full-duplex Ethernet controller using the 
  embedded MAC.
  The controller uses the 1Gb/sec-only clocking arrangement
  shown in UG194 Figure 6-6.
  It uses a simplified version of the main CPU to
  do initial frame processing.
*/

module Ethernet(
  input  reset,
  input  ethTXclock,  //125 MHz 50% duty cycle clock
  input  clock, //100 MHz cllock
  input  [3:0]  whichCore,  //the number of this core
  input  [3:0]  CopyCore,
  //Ring signals
  input  [31:0] RingIn,
  input  [3:0]  SlotTypeIn,
  input  [3:0]  SourceIn,
  output [31:0] RingOut,
  output [3:0]  SlotTypeOut,
  output [3:0]  SourceOut,
  input  [31:0] RDreturn,
  input  [3:0]  RDdest,

  //RS232 signals
  input  RxD,
  output TxD,
  output releaseRS232,

  //I2C signals for reading the MAC address
  input SDAin,
  output SDAx,
  output SCLx,

  //GMII interface
  output reg   [7:0]  GMII_TXD_0,
  output reg          GMII_TX_EN_0,
  output reg          GMII_TX_ER_0,
  output          GMII_TX_CLK_0, //to PHY. Made in ODDR
  input    [7:0]  GMII_RXD_0,
  input           GMII_RX_DV_0,
  input           GMII_RX_CLK_0 , //from PHY. Goes through BUFG
  output          GMII_RESET_B
);

  wire [7:0] preGMII_TXD_0;
  wire preGMII_TX_EN_0;
  wire preGMII_TX_ER_0;
 
  wire clientRXclock;
  wire RXclockDelay;
  wire [7:0] RXdataDelay;
  reg [7:0] RXdataDelayReg;
  wire RXdvDelay;
  reg RXdvDelayReg;

  wire [7:0] RXdata;  //received data from MAC
  wire RXdataValid;          //received data valid
  wire RXgoodFrame;
  wire RXbadFrame;

  wire [7:0] TXdata;       //data to MAC
  wire TXdataValid;
  wire TXack;

  wire [9:0] receiverAddress;  //header data to the SimpleRisc data memory from EthWriter
  wire [31:0] receiverData;
  wire receiverWrite;
  wire headerRead;

  wire [31:0] msgrRingOut;
  wire [3:0]  msgrSlotTypeOut;
  wire [3:0]  msgrSourceOut;
  wire msgrDriveRing;
  wire msgrWantsToken;
  wire msgrAcquireToken;
  wire phyReset;
  
  wire [31:0] etherRingOut;
  wire [3:0]  etherSlotTypeOut;
  wire [3:0]  etherSourceOut;
  wire etherDriveRing;
  wire etherWantsToken;
  wire etherAcquireToken;

  wire [27:0] RXdmaAddr;  //the receive dma address fifo from the SimpleRisc
  wire RXdmaEmpty;
  wire readRXdmaAddr;

  wire [12:0] RXframeLength;  //goes to the frameLength fifo in the SimpleRisc
  wire writeFrameLength;

  wire [27:0] TXdmaAddr;     //the transmit dma address from the SimpleRisc
  wire readTXdmaAddr;
  wire [26:0] TXdmaLength;  //DMbase (7), header length (5),source core number (4), and payload length (11)
  wire TXdmaEmpty;


  //signals to/from EthReader 
  wire [31:0] transmitData;
  wire transmitWrite;
  wire stopDMA;
  wire [47:4] SMACaddr;
  wire [31:0] DMdata;
  wire [9:0] DMaddr; //address to DM for transmit heade

  //signals to/from the EthWriter
  wire [32:0] memoryData;  //bit 31 means end of received frame.
  wire dataReady;
  wire readWord;
 
  (* KEEP = "TRUE" *) reg[2:0] RCfsm;  //the ring controller state machine
  (* KEEP = "TRUE" *) reg[1:0] RDfsm;  //the transmit machine
  (* KEEP = "TRUE" *) reg [2:0] WRfsm; //the receive machine
  reg [7:0] burstLength;

  wire readRequest;
  wire writeRequest;

  parameter RCidle = 0;
  parameter RCwaitToken = 1;
  parameter RCwaitN = 2;
  parameter RCsendBoth = 3;
  parameter RCsendRAonly = 4;
  parameter RCsendWA = 5;
  parameter RCsendData = 6; 

  // To remember which requests were asserted
  //at the time the token came by, we need two
  //auxiliary bits:

  reg readRequested;
  reg writeRequested;

  reg [27:0] TXrdAddr;  //loaded by the transmit DMA machine
  reg [5:0]  TXrdLength; //loaded by the transmit DMA machine. 
                         //Number of 8-word blocks needed
  reg [8:0]  TXwordCount; //number of words to send to the fifo
    
  reg  [27:0] RXwrAddr;  //loaded by the receive DMA machine
  wire [31:0] TXreadAddress; //addresses that go on the ring
  wire [31:0] RXwriteAddress;

  wire readStage;
  wire writeStage;
  wire [31:0] stageData;
  wire stageEmpty;
  wire stageFull;
  reg [5:0] stageCnt;

//----------------End of Declarations------------------

/* 
There are three FSMs: A ring controler that controls access to the ring,
the transmit DMA,and the receive DMA machines.  

The ring controller waits for a read or write 
request from the DMA machines.  When it gets one, it waits for a Token
and injects the length into the ring (1, 9, or 10 depending on which 
controller(s) are requesting), waits for the end of the train, and
injects either:
(1) a ReadAddress (read & ~write), 
(2) a read address followed by write data followed by a WriteAddress 
    (read & write), or
(3) write data followed by a write address (write & ~read)


----------------------------------------------------------------

The transmit DMA machine starts when the TXdmaEmpty flag goes false.
The machine loads the readLength register and the transmitData fifo
with the frame length and loads the readAddress register with the
dma address (in cache lines).
   
It then, if stopDMA is false),requests a read from the ring
controler.  When it receives a reply, it decrements the block count and
idles, but will immediately make another request if the block
count is nonzero. 

The number of blocks needed is
TXdmaLength[10:5] + (| TXdmaLength[4:0])

---------------------------------------------------------------

The receive DMA machine is a bit trickier than the transmit
machine, since we don't know the length of the frame until it
is finished, and we can't start the DMA until we have an 
address from the SimpleRISC.

When a frame arrives, the EthWriter puts it in a 
large fifo.  The output of this fifo is memoryData, and the
nonempty flag is dataReady.  If memoryData[32] = 1, this is
the final entry of the frame, and memoryData contains the frame
length (in bytes).  An entry is read from the fifo by asserting
readData.

The receive machine starts when it is idle and the first data word is sent to
the staging fifo (rxStageFifo). It waits for a write address to appear 
(~RXdmaEmpty) and transfers the address into RXwrAddr.

It then issues a writeRequest whenever stageOK is true (stageCnt >= 8), or
when memoryData[32] == 1, indicating that the frame has ended.

The stage will no longer be loaded when memory[32] == 1, but the 
stage must be drained, so the controller continues to assert
writeRequests until the stage becomes empty.  At this time,
any words required to fill out the 8-word burst are repetitions
of the previous word (since the stage isn't read when empty).

On the last word of a write burst with the stage empty and memoryData[32] true,
the machine transitions to writeLength. The final word of memoryData is written
to the SimpleRISC's RXframeLength queue (writeFrameLength is asserted), the 
last entry is read from memoryData, and the machine idles, awaiting the
next frame. 
*/

//----------------The interaction of ethernet core to the ring-----------------
  assign TXreadAddress =  {4'b0001, TXrdAddr};
  assign RXwriteAddress = {4'b0000, RXwrAddr};
  
  assign etherWantsToken = (RCfsm == RCwaitToken);
  assign etherDriveRing = ((RCfsm == RCwaitToken) & etherAcquireToken) | 
                           (RCfsm == RCsendData) | (RCfsm == RCsendWA);
    
  wire RCsendingRA = 
    (RCfsm == RCwaitToken) & etherAcquireToken & readRequested;

  wire RCsendingWA = (RCfsm == RCsendWA);
  
  wire RCsendingData = 
    ((RCfsm == RCwaitToken) & etherAcquireToken & ~readRequested) |
    (RCfsm == RCsendData);

  assign etherSourceOut = whichCore;
  assign etherSlotTypeOut = 
    (RCsendingRA | RCsendingWA) ? `Address : `WriteData;
  assign etherRingOut = (RCsendingRA) ? TXreadAddress :
                        (RCsendingWA) ? RXwriteAddress : 
                                        stageData;
                                        
  always @(posedge clock)
    if (reset) RCfsm <= RCidle;
    else case(RCfsm)
      RCidle: if(readRequest | writeRequest) begin
        readRequested <= readRequest;
        writeRequested <= writeRequest;
        RCfsm <= RCwaitToken; //have something to do
      end

      RCwaitToken: if (etherAcquireToken) begin
        if (readRequested & ~writeRequested) RCfsm <= RCidle; //send RA, idle
        else if(writeRequested & ~readRequested) begin
          // send data + WA
          burstLength <= 7;
          RCfsm <= RCsendData;        
        end else begin
          // send RA then send data + WA
          burstLength <= 8; 
          RCfsm <= RCsendData;      
        end
      end

      RCsendData: begin
        burstLength <= burstLength - 1;
        if(burstLength == 1) RCfsm <= RCsendWA;
      end

      RCsendWA: RCfsm <= RCidle;
    endcase

//----------The transmit DMA machine and surrounding logic:------------
  parameter RDidle = 0; //read FSM states
  parameter RDgetAddr = 1;  //get the address and length from TX queues
  parameter RDrequest = 2;
  parameter RDdecAddr = 3;
  
  always @(posedge clock) begin
    if(reset) RDfsm <= RDidle;
	 else case(RDfsm)
	   RDidle: if(~TXdmaEmpty & (TXwordCount == 0)) RDfsm <= RDgetAddr;
		
		RDgetAddr: begin
		  TXrdAddr <= TXdmaAddr;
		  TXrdLength <= TXdmaLength[10:5] + (| TXdmaLength[4:0]);  //this is the number of cache lines to fetch (not the number of words to
//send to the FIFO.
		  RDfsm <= RDrequest;
      end
		
		RDrequest: if (RCsendingRA)
		  RDfsm <= RDdecAddr;  //the ring controller is fetching the data
		  
		RDdecAddr: begin
        TXrdLength <= TXrdLength - 1;
		  TXrdAddr <= TXrdAddr + 1;
        if(TXrdLength == 1) RDfsm <= RDidle;
        else RDfsm <= RDrequest;		  
		end
		
    endcase
  end

  always @(posedge clock) if(RDfsm == RDgetAddr) TXwordCount <= TXdmaLength[10:2] + (TXdmaLength[1] | TXdmaLength[0]) ; //number of 4-byte words to transfer
    else if((RDdest == whichCore) & (TXwordCount != 0)) TXwordCount <= TXwordCount - 1;
	 
  assign readTXdmaAddr = (RDfsm == RDgetAddr);
  
  assign readRequest = (RDfsm == RDrequest) & ~stopDMA;  //don't make a request if the write FIFO is nearly full.
  
//The read machine fetches data without waiting for it to arrive.  When
//it does arrive, it is sent to the EthReader unless the TXwordCount is zero.
  assign transmitData = (RDfsm == RDgetAddr) ? {5'b0, TXdmaLength}: //DMbase (7),header length (5), source core (4), payload length (11)
    RDreturn;  //read data from memory
	 
  assign transmitWrite = ((RDdest == whichCore) & (TXwordCount != 0) ) |
    (RDfsm == RDgetAddr);

//-----------------------------The receive FSM and logic:-------------------

parameter WRidle = 0; //FSM states
parameter WRgetAddr = 1;
parameter WRrequest = 2;
parameter WRsendLength = 3;
parameter WRdiscard = 4;
parameter WRlastDiscard = 5;

queueN #(.width(32)) rxStageFifo (
	.clk(clock),
	.din(memoryData[31:0]), 
	.rd_en(readStage),
	.rst(reset),
	.wr_en(writeStage),
	.dout(stageData), 
	.empty(stageEmpty),
	.full());

always @(posedge clock)
   if(reset) stageCnt <= 0;
	else if( readStage & ~writeStage) stageCnt <= stageCnt - 1;
	else if( writeStage & ~readStage) stageCnt <= stageCnt + 1;
	
assign writeStage = dataReady & ~memoryData[32] & ~stageFull;
assign stageFull = stageCnt[5];  //rxStageFifo is 64 deep, so this is safe
assign stageOK = stageCnt >= 8;  //stage has enough words to request a transfer
assign readStage =  (RCsendingData & ~stageEmpty) | 
                    ((WRfsm == WRdiscard) & ~stageEmpty);
assign writeRequest = (WRfsm == WRrequest) & (stageOK | (~stageEmpty & memoryData[32]));
assign readWord = writeStage | (WRfsm == WRsendLength) | (WRfsm == WRlastDiscard);
assign RXframeLength = memoryData[12:0];  //byteCount[10:0], goodFrame, badFrame
assign writeFrameLength = (WRfsm == WRsendLength);
assign readRXdmaAddr = (WRfsm == WRgetAddr) & ~RXdmaEmpty;

always @(posedge clock) begin
  if(reset) WRfsm <= WRidle;
  else case(WRfsm)
    WRidle: if(writeStage) WRfsm <= WRgetAddr;
	 
	 WRgetAddr:  if(~RXdmaEmpty) begin
	   RXwrAddr <= RXdmaAddr;
		if(RXdmaAddr != 0) WRfsm <= WRrequest;
		else WRfsm <= WRdiscard;  //zero address means discard the frame
	 end
	 
	 WRrequest: begin
	   if (RCsendingWA) RXwrAddr <= RXwrAddr + 1;   
		if((stageEmpty) & memoryData[32]) WRfsm <= WRsendLength;
	 end	
	 WRsendLength: WRfsm <= WRidle;
	 
	 WRdiscard: if(stageEmpty & memoryData[32]) WRfsm <= WRlastDiscard;
	 
	 WRlastDiscard: WRfsm <= WRidle;
  endcase
end

//-----Overall core interaction with the ring similar as in Risc.v-------------
  reg state;
  localparam idle = 0;  
  localparam tokenHeld = 1;

  wire coreHasToken = (SlotTypeIn == `Token);// | (state == tokenHeld);  
  wire coreSendNewToken = 
    ((coreHasToken | (state == tokenHeld)) & ~msgrDriveRing & ~etherDriveRing);

  assign msgrAcquireToken = 
    (coreHasToken & msgrWantsToken);
  assign etherAcquireToken = 
    (coreHasToken & ~msgrWantsToken & etherWantsToken);

  always @(posedge clock) begin
    if (reset) state <= idle;
    else case(state)
      idle: if(SlotTypeIn == `Token) begin
        if (msgrWantsToken | etherWantsToken) state <= tokenHeld;
      end
    
      tokenHeld: if (coreSendNewToken) state <= idle;
    endcase
  end

  // This handles when core needs to drive the ring to either send new token
  // or Nullify messages
  wire coreDriveRing = coreSendNewToken | (SlotTypeIn == `Token) | 
                      (SourceIn == whichCore & SlotTypeIn != `Null);
  wire [31:0] coreRingOut = 32'b0;
  wire [3:0]  coreSourceOut = whichCore;
  wire [3:0]  coreSlotTypeOut = coreSendNewToken ? `Token : `Null;
  
  assign SourceOut =
      msgrDriveRing  ? msgrSourceOut :
      etherDriveRing ? etherSourceOut :
      coreDriveRing  ? coreSourceOut  :
      SourceIn;

  assign RingOut =
     msgrDriveRing  ? msgrRingOut  :
     etherDriveRing ? etherRingOut :
     coreDriveRing  ? coreRingOut  :
     RingIn;

  assign SlotTypeOut =
     msgrDriveRing  ? msgrSlotTypeOut  : 
     etherDriveRing ? etherSlotTypeOut :
     coreDriveRing  ? coreSlotTypeOut  :
     SlotTypeIn;

//-------------------------------Other stuff---------------------------------

 always @(posedge ethTXclock) begin
   GMII_TXD_0 <= preGMII_TXD_0;
   GMII_TX_EN_0 <= preGMII_TX_EN_0;
   GMII_TX_ER_0 <= preGMII_TX_ER_0;
 end
    
 assign GMII_RESET_B = ~(reset | phyReset);

 
//ODDR for Phy Clock
  ODDR GMIIoddr (
      .Q(GMII_TX_CLK_0),.C(ethTXclock),.CE(1'b1),
      .D1(1'b0), .D2(1'b1), .R(reset), .S(1'b0)
  );
  
//IDELAYs and BUFG for the Receive data and clock
	 IDELAY #(
    .IOBDELAY_TYPE("FIXED"), // "DEFAULT", "FIXED" or "VARIABLE"
    .IOBDELAY_VALUE(0) // Any value from 0 to 63
     ) RXclockBlk
    (
	   .I(GMII_RX_CLK_0),.O(RXclockDelay),.C(1'b0),
      .CE(1'b0), .INC(1'b0),.RST(1'b0)
    );

    BUFG bufgClientRx (.I(RXclockDelay), .O(clientRXclock));
	 
	 IDELAY #(
    .IOBDELAY_TYPE("FIXED"), // "DEFAULT", "FIXED" or "VARIABLE"
    .IOBDELAY_VALUE(20) // Any value from 0 to 63
     ) RXdvBlock
    (
	   .I(GMII_RX_DV_0), .O(RXdvDelay), .C(1'b0),
      .CE(1'b0), .INC(1'b0),.RST(1'b0)
    );

always @(posedge clientRXclock) begin  //register the delayed RXdata.
  RXdataDelayReg <= RXdataDelay;
  RXdvDelayReg <= RXdvDelay;
end

genvar idly;
generate
  for(idly = 0; idly < 8; idly = idly + 1)
  begin: dlyBlock
	 IDELAY #(
    .IOBDELAY_TYPE("FIXED"), // "DEFAULT", "FIXED" or "VARIABLE"
    .IOBDELAY_VALUE(20) // Any value from 0 to 63
     ) RXdataBlock
    (
	   .I(GMII_RXD_0[idly]), .O(RXdataDelay[idly]), .C(1'b0),
      .CE(1'b0), .INC(1'b0),.RST(1'b0)
    );
  end
endgenerate  

 
//Instantiate the simple RISC
etherRISC controlRisc(
 .reset(reset),
 .clock(clock),
 .whichCore(whichCore),
 .CopyCore(CopyCore),
 .RingIn(RingIn),
 .SlotTypeIn(SlotTypeIn),
 .SourceIn(SourceIn),
 .msgrSlotTypeOut(msgrSlotTypeOut),
 .msgrSourceOut(msgrSourceOut),
 .msgrRingOut(msgrRingOut),
 .msgrDriveRing(msgrDriveRing),
 .msgrWantsToken(msgrWantsToken),
 .msgrAcquireToken(msgrAcquireToken),
 .RxD(RxD),
 .TxD(TxD),
 .SCLx(SCLx),
 .SDAx(SDAx),
 .SDAin(SDAin),
 .releaseRS232(releaseRS232),
 .receiverAddress(receiverAddress), //from EthWriter
 .receiverData(receiverData), //from EthWriter
 .receiverWrite(receiverWrite), //from EthWriter
 .clientRXclock(clientRXclock),
 .headerRead(headerRead),  //to EthWriter
 .RXheaderCountNonzero(headerCountNonZero),  //from EthWriter
 
 .RXdmaAddr(RXdmaAddr),
 .RXdmaEmpty(RXdmaEmpty),
 .readRXdmaAddr(readRXdmaAddr),

 .RXframeLength(RXframeLength),  //11 bit frame length (bytes), goodFrame, badFrame
 .writeFrameLength(writeFrameLength),

 .TXdmaAddr(TXdmaAddr),
 .TXdmaLength(TXdmaLength),
 .TXdmaEmpty(TXdmaEmpty),
 .readTXdmaAddr(readTXdmaAddr),
 .SMACaddr(SMACaddr),
 .phyReset(phyReset),
 .DMaddr(DMaddr),
 .DMdata(DMdata),
 .readClock(ethTXclock)
  
 );
  
//Instantiate the MAC
MAC etherMAC(
    // Client Receiver Interface
    .RXclockOut(),          //output
    .RXclockIn(clientRXclock),        //input
    .RXdata(RXdata),                  //output   [7:0]
    .RXdataValid(RXdataValid),        //output
    .RXgoodFrame(RXgoodFrame),        //output
    .RXbadFrame(RXbadFrame),          //output
    .TXclockIn(ethTXclock),                //input
    .TXdata(TXdata),                  //input    [7:0]
    .TXdataValid(TXdataValid),        //input
    .TXdataValidMSW(1'b0),            //input
    .TXack(TXack),                    //output
    .TXfirstByte(1'b0),               //input
    .TXunderrun(1'b0),                //input

    // MAC Control Interface
    .PauseRequest(1'b0),
    .PauseValue(16'b0),

    // Clock Signals
    .TXgmiiMiiClockIn(ethTXclock),
	 .MIItxClock(1'b0),

    // GMII Interface
    .GMIItxData(preGMII_TXD_0),          //output   [7:0]
    .GMIItxEnable(preGMII_TX_EN_0),      //output
    .GMIItxError(preGMII_TX_ER_0),       //output
    .GMIIrxData(RXdataDelayReg),         //input    [7:0]  
    .GMIIrxDataValid(RXdvDelayReg),      //input
    .GMIIrxClock(clientRXclock),      //input
    .DCMlocked(1'b1),
    // Asynchronous Reset
    .Reset(reset)
	 );

//Instantiate the EthWriter

EthWriter ewriter(
   .CLK(clock),
   .reset(reset),
   .clientRXclock(clientRXclock),
   .RXdata(RXdata),  //data from MAC
   .RXdataValid(RXdataValid),
   .RXgoodFrame(RXgoodFrame),
   .RXbadFrame(RXbadFrame),
   .receiverAddress(receiverAddress),  //data, address, and strobe to CPU data memory
   .receiverData(receiverData),
   .receiverWrite(receiverWrite),
	.headerCountNonZero(headerCountNonZero),
   .headerRead(headerRead),  //CPU has read the header. This is in the clock domain
   .memoryData(memoryData),
   .dataReady(dataReady),
   .readWord(readWord)
);

//Instantiate the EthReader


EthReader ereader(

  .clock(clock),
  .ethTXclock(ethTXclock),
  .resetIn(reset),
  .transmitData(transmitData), //data from dma read engine
  .transmitWriteIn(transmitWrite),  //write TX fifo (in clock domain)
  .stopDMA(stopDMA),
  .TXdata(TXdata),  //transmit data to MAC
  .TXdataValid(TXdataValid),   //data valid to MAC
  .TXack(TXack),          //frame accepted by MAC
  .SMACaddr(SMACaddr),
  .DMaddr(DMaddr),
  .DMdata(DMdata)
   );

	 
endmodule
