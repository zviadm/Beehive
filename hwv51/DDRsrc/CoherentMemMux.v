`timescale 1ns / 1ps

/*
This module is a memory controller using the ring interfacing scheme.

Uses a separate ring to return read data

Created By: Microsoft,

This version also supports coherent DCaches by having a Resend Message queue
and instantiating mmsFSMcoherent module.

Modified By: Zviad Metreveli
*/

module CoherentMemMux (
  input clock,
  input clock90,
  input reset,

  //interface signals to the ring
  input[31:0] RingIn,
  input [3:0] SlotTypeIn,
  input [3:0] SourceIn,
  output [31:0] RingOut,
  output [3:0] SlotTypeOut,
  output [3:0] SourceOut,

  output [31:0] RDreturn,  //separate path for read data return
  output [3:0] RDdest,

  //Signals to the DIMMs
  inout [63:0] DQ,       //the DQ pins
  inout [7:0] DQS,      //the DQS pins
  inout [7:0] DQS_L,
  output [1:0] DIMMCK,    //differential clock to the DIMM
  output [1:0] DIMMCKL,
  output [13:0] A,       //addresses to DIMMs
  output [2:0] BA,       //bank address to DIMMs
  output [7:0] DM,
  output [1:0] RS,       //rank select
  output RAS,
  output CAS,
  output WE,
  output [1:0] ODT,
  output [1:0] ClkEn,     //common clock enable for both DIMMs. SSTL1_8

  //DDR clocks
  input MCLK,
  input MCLK90,

  //TC5 signals
  input Ph0,          //TC5 clock
  output TxD,         //RS232 transmit data
  input  RxD,         //RS232 received data
  output [3:0] SelectRS232,
  input ReleaseRS232,
  output [7:0] LED,

  //Outputs to the Chrontel chip:
  output [11:0] DVIdata,
  output DVIclkP,
  output DVIclkN,
  output DVIhsync,
  output DVIvsync,
  output DVIde, //data enable
  output DVIresetB, //low true DVIreset
  output verticalFP,
  input [25:0] displayAddress  
);

  //TC5 interface signals
  wire [33:0] LastALU;
  wire injectTC5address;
  wire CalFailed;
  wire InhibitDDR;
  wire Force;
  wire DDRclockEnable;
  wire ResetDDR;
  wire StartDQCal0;

  //ddrController signals
  wire [127:0] MemData;
  wire [127:0] MemWriteData;
  wire writeAF;
  wire writeWB;
  wire RBempty;
  wire ReadRB;
  wire [25:0] AFin;
  wire readIn;
  wire wbFull, afFull;
  
  // FSM state, and wires that queues up messages in MQ
  reg [1:0] state;
  
  // resend queue wires
  wire [39:0] resendQin;
  wire rdResendQ, wrResendQ;
  wire [3:0] resendQtype, resendQdest;
  wire [31:0] resendQout;
  wire resendQempty;

  // address and read data from/to the display controller
  wire RDready;
  wire readReq;
  wire readAck;
  wire [25:0] RA;
  wire [127:0] RDtoDC;
  
  // wires to MemOpQ
  wire memOpQempty;
  wire [39:0] memOpQIn;
  wire wrMemOpQ, rdMemOpQ;
  wire [3:0] memOpQdest;
  wire [3:0] memOpQtype;
  wire [31:0] memOpQout;
  
  // wires to WriteDataQ
  wire writeDataQempty;
  reg [1:0] wcnt;
  reg [31:0] w0, w1, w2, w3;
  reg wrWriteDataQ;
  wire rdWriteDataQ;
  wire [127:0] writeDataQout;
  reg [15:0] writeDataQelts;
  wire WDQalmostFull;
    
  localparam idle = 0; //States
  localparam dumpResendQ = 1;
  localparam waitToken = 2;

//---------------------End of Declarations-----------------

  always @(posedge clock) 
    if(reset) state <= idle;
    else case(state)
      idle: if(~InhibitDDR & ~ResetDDR & ~WDQalmostFull) state <= dumpResendQ;

      dumpResendQ: if (resendQempty) state <= waitToken;

      waitToken: 
        if(SlotTypeIn == `Token) begin
          if(~InhibitDDR & ~ResetDDR & ~WDQalmostFull) state <= dumpResendQ;
          else state <= idle;
        end
    endcase
    
  wire nullifyMessage = (SlotTypeIn == `Token) | (SourceIn == 4'b0) | 
    (SlotTypeIn == `Address & RingIn[31]);
  
  assign SlotTypeOut =
    (state == dumpResendQ & resendQempty)    ? `Token :
    (state == dumpResendQ & ~resendQempty)   ? resendQtype :
    nullifyMessage                           ? `Null : SlotTypeIn;

  assign RingOut = 
    (state == dumpResendQ & resendQempty)    ? 32'b0 :
    (state == dumpResendQ & ~resendQempty)   ? resendQout :
    nullifyMessage                           ? 32'b0 : RingIn;

  assign SourceOut = 
    (state == dumpResendQ & resendQempty)    ? 4'b0 :
    (state == dumpResendQ & ~resendQempty)   ? resendQdest :
    nullifyMessage                           ? 4'b0 : SourceIn;

  //Ack display controller's address.
  assign readAck = ~(SlotTypeIn == `Address) & readReq & memOpQempty; 
  
  // decided what should go into memOpQ, stuff from ring or from DC  
  assign wrMemOpQ = (SlotTypeIn == `Address) | (readAck);
  assign memOpQIn = 
    (SlotTypeIn == `Address)    ? {SourceIn, SlotTypeIn, RingIn} : 
                                  {4'b0000, `Address, {6'b000100, RA}};
  
  // write to writeDataQ, also count number of elements in writeDataQ
  always @(posedge clock) begin
    if (reset) begin
      wcnt <= 0;
      writeDataQelts <= 0;
    end
    else begin
      if (SlotTypeIn == `WriteData) begin
        // get w0, w1, w2 & w3
        if (wcnt == 0) w0 <= RingIn;
        else if (wcnt == 1) w1 <= RingIn;
        else if (wcnt == 2) w2 <= RingIn;
        else if (wcnt == 3) w3 <= RingIn;    
        
        wcnt <= wcnt + 1;
      end

      wrWriteDataQ <= (wcnt == 3);
      
      if (wrWriteDataQ && ~rdWriteDataQ) 
        writeDataQelts <= writeDataQelts + 1;
      else if (~wrWriteDataQ && rdWriteDataQ) 
        writeDataQelts <= writeDataQelts - 1;
    end
  end
  
  // check if writeDataQ is almost full in this case we should not release new 
  // token. This might not be necessary but just to be safe we do it, so that 
  // WDQ does not overflow. also depth of WDQ now is 1024.
  assign WDQalmostFull = (writeDataQelts[15:9] != 0);

  assign rdResendQ = (state == dumpResendQ) & ~resendQempty;    
  resendQ resendQueue (
    .clk(clock),
    .rst(reset),
    .din(resendQin), // Bus [39 : 0] 
    .wr_en(wrResendQ),
    .rd_en(rdResendQ),
    .dout({resendQdest, resendQtype, resendQout}), // Bus [39 : 0] 
    .full(),
    .empty(resendQempty));
    
  // Queue to store memory operations in (read/write)
  memOpQ memOpQueue (
    .clk(clock),
    .rst(reset),
    .din(memOpQIn),
    .wr_en(wrMemOpQ),
    .rd_en(rdMemOpQ),
    .dout({memOpQdest, memOpQtype, memOpQout}),
    .full(),
    .empty(memOpQempty)
  );
  
  // Queue to store write data
  writeDataQ writeDataQueue (
    .clk(clock),
    .rst(reset),
    .din({w3, w2, w1, w0}),
    .wr_en(wrWriteDataQ),
    .rd_en(rdWriteDataQ),
    .dout(writeDataQout),
    .full(),
    .empty(writeDataQempty)
  );

  mmsFSMcoherentL2 mmsFSM (
    .clock(clock),
    .reset(reset),
    // mem op queue
    .memOpQempty(memOpQempty),
    .rdMemOp(rdMemOpQ),
    .memOpType(memOpQtype),
    .memOpDest(memOpQdest),
    .memOpData(memOpQout),
    // write data queue
    .writeDataQempty(writeDataQempty),
    .rdWriteData(rdWriteDataQ),
    .writeDataIn(writeDataQout),
    // resend queue
    .wrResend(wrResendQ),
    .resendOut(resendQin),
    // read data queue
    .rbEmpty(RBempty),
    .rdRB(ReadRB),
    .readData(MemData),
    
    // wires to DDR controller
    .wrAF(writeAF),
    .afAddress(AFin),
    .afRead(readIn),
    .wrWB(writeWB),
    .writeData(MemWriteData),	
    .wbFull(wbFull),
    .afFull(afFull),

    // RD outputs
    .RDreturn(RDreturn),
    .RDdest(RDdest), 
    .RDtoDC(RDtoDC),
    .wrRDtoDC(RDready)
  );
    
  //Instantiate the TC5
  TinyComp TC5(
    .Ph0(Ph0),
    .Reset(reset),
    .TxD(TxD),
    .RxD(RxD),
    .StartDQCal0(StartDQCal0),
    .LastALU(LastALU),
    .injectTC5address(injectTC5address),
    .CalFailed(CalFailed),
    .InhibitDDR(InhibitDDR),
    .Force(Force), .DDRclockEnable(DDRclockEnable),
    .ResetDDR(ResetDDR), 
    .SelectRS232(SelectRS232),
    .ReleaseRS232(ReleaseRS232),
    .LED(LED)
  );

  //Instantiate the DDR2 controller
  ddrController ddra(
    .CLK(clock),
    .MCLK(MCLK),
    .MCLK90(MCLK90),
    .Reset(reset),
    .CalFailed(CalFailed),
    .DDRclockEnable(DDRclockEnable),
    .Address(AFin),
    .WriteAF(writeAF),
    .Read(readIn),
    .ReadData(MemData),
    .ReadRB(ReadRB),
    .WriteData(MemWriteData),

    .DQ(DQ), //the DQ pins
    .DQS(DQS), //the DQS pins
    .DQS_L(DQS_L),
    .DIMMCK(DIMMCK),  //differential clock to the two DIMMs
    .DIMMCKL(DIMMCKL),
    .A(A), //addresses to DIMMs
    .BA(BA), //bank address to DIMMs
    .DM(DM),
    .RS(RS), //rank select
    .RAS(RAS),
    .CAS(CAS),
    .WE(WE),
    .ODT(ODT),  //two ODTs, one for each DIMM
    .ClkEn(ClkEn), //common clock enable for both DIMMs. SSTL1_8
    .StartDQCal0(StartDQCal0),
    .LastALU(LastALU[33:0]),
    .injectTC5address(injectTC5address),
    .InhibitDDR(InhibitDDR),
    .Force(Force),

    .ResetDDR(ResetDDR),
    .SingleError(),
    .DoubleError(),
    .RBempty(RBempty),
    .RBfull(),
    .WBfull(wbFull),
    .WriteWB(writeWB),
    .WBclock(clock),
    .RBclock(clock),
    .AFclock(clock),
    .AFfull(afFull)
  );

  //instantiate the display controller
  displayCon controller(
    // .Ph0(Ph0),
    .clock(clock),
    .clock90(clock90),
    .reset(reset),
    .DVIdata(DVIdata),
    .DVIclkP(DVIclkP),
    .DVIclkN(DVIclkN),
    .DVIhsync(DVIhsync),
    .DVIvsync(DVIvsync),
    .DVIde(DVIde),
    .DVIresetB(DVIresetB),
    .RD({RDtoDC[119:96], RDtoDC[87:64], RDtoDC[55:32], RDtoDC[23:0]}),
    .RDready(RDready),
    .readReq(readReq),
    .readAck(readAck),
    .RA(RA),
    .verticalFP(verticalFP),
    .displayAddress(displayAddress)
  );
endmodule
