`timescale 1ns / 1ps

module newMemMux (
/*
This module is a memory controller using the ring interfacing scheme.
Its inputs are the outputs of the ring, and it is the source for
slots injected into the ring.

This version uses a separate ring to return read data
*/
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
  inout [63:0] DQ,         //the DQ pins
  inout [7:0] DQS,         //the DQS pins
  inout [7:0] DQS_L,
  output [1:0] DIMMCK,     //differential clock to the DIMM
  output [1:0] DIMMCKL,
  output [13:0] A,         //addresses to DIMMs
  output [2:0] BA,         //bank address to DIMMs
  output [7:0] DM,
  output [1:0] RS,         //rank select
  output RAS,
  output CAS,
  output WE,
  output [1:0] ODT,
  output [1:0] ClkEn,      //common clock enable for both DIMMs. SSTL1_8
 
  //DDR clocks
  input MCLK,
  input MCLK90,

  //TC5 signals
  input Ph0,              //TC5 clock
  output TxD,             //RS232 transmit data
  input  RxD,             //RS232 received data
  output [3:0] SelectRS232,
  input ReleaseRS232,
  output [7:0] LED,

  //Outputs to the Chrontel chip:
  output [11:0] DVIdata,
  output DVIclkP,
  output DVIclkN,
  output DVIhsync,
  output DVIvsync,
  output DVIde,           //data enable
  output DVIresetB,       //low true DVIreset
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

  //ddrController signals
  wire [127:0] MemData;
  reg [31:0] wr0, wr1, wr2, wr3;
  wire takeWD;
  wire writeAF;
  reg writeWB;
  wire RBempty;
  wire ReadRB;
  reg [7:0] burstLength;
  reg [1:0] wcnt;
  reg [2:0] rcnt;
  reg [2:0] state;  
  wire [8:0] destIn; //cjt: now use 9 bits of dest (+5 for meters)
  wire [8:0] dest; //destination for read data

  wire [25:0] AFin;
  wire readIn;
  wire readDest;
  wire writeDest;
  reg [5:0] rif;

  //address and read data from/to the display controller
  wire RDready;
  wire readReq;
  wire readAck;
  wire [25:0] RA;
  reg dd1;

  //FSM States
  localparam idle = 0;
  localparam sendToken = 1;
  localparam waitToken = 2;
  localparam waitData = 3;

  //Slot Types
  localparam Null = 7;
  localparam Token = 1;
  localparam Address = 2;
  localparam WriteData = 3;
  localparam ReadData = 4;
  localparam Message = 8;
  localparam Lock = 9;
  localparam LockFail = 10;

//---------------------End of Declarations-----------------

  //Read return bus destination.
  assign RDdest = (~RBempty & ~dest[4]) ? dest[3:0] : 4'b0000;  

  always @(posedge clock) 
    if(SlotTypeIn == Token) burstLength <= RingIn[7:0];
    else if(burstLength != 0) burstLength <= burstLength - 1;

  assign ReadRB = (~RBempty & ~dest[4] & (rcnt[1:0] == 3)) | 
                  (~RBempty & dest[4]);

  //cjt
  // destIn now 9 bits.  Top four bits indicate type of read:
  // 0---   regular memory read
  // 1abc   read meters (abc = which bank of 8 meters)  
  // last eight cache lines => meters
  wire [27:0] meter_cache_line = 28'hFFFFFF8;
  wire rd_meters = (RingIn[27:3] == meter_cache_line[27:3]);
  assign destIn = 
    (SlotTypeIn == Address) ? {rd_meters, RingIn[2:0], 1'b0, SourceIn} :
    9'b000011111;

  assign writeDest = ((SlotTypeIn == Address) & RingIn[28]) | readAck;

  always @(posedge clock) 
    if (reset | dd1) dd1 <= 0;
    else if((dest == 31) & ~RBempty) dd1 <= 1;
  
  assign readDest = (~dest[4] & ~RBempty & (rcnt == 7)) | 
                    (dest[4] & ~RBempty & dd1);   

  //rif counts reads-in-flight
  always @(posedge clock) 
    if(reset) rif <= 0;
    else begin
      if(writeDest & ~readDest) rif <= rif + 1;
      else if(~writeDest & readDest) rif <= rif - 1;
    end

  //Ack display controller's address.
  assign readAck = ~(SlotTypeIn == Address) & readReq & ~rif[5]; 
  //display controller data is ready.
  assign RDready = (~RBempty & (dest == 31)); 

  assign AFin = (SlotTypeIn == Address) ? RingIn[25:0] : RA;
  assign readIn = writeDest;
  assign writeAF = (SlotTypeIn == Address) | readAck;

  //rcnt and wcnt only change in response to ring-initiated operations.
  always @(posedge clock) 
    if(reset) wcnt <= 0; else if(SlotTypeIn == WriteData) wcnt <= wcnt + 1;
  always @(posedge clock) 
    if(reset) rcnt <= 0; else if (~RBempty & ~dest[4]) rcnt <= rcnt + 1;

  assign takeWD = (SlotTypeIn == WriteData);

  always @(posedge clock) 
    if(reset) writeWB <= 0; else writeWB <= (takeWD & (wcnt == 3));

  always @(posedge clock) if(takeWD)
    if     (wcnt == 0) wr0 <= RingIn;
    else if(wcnt == 1) wr1 <= RingIn;
    else if(wcnt == 2) wr2 <= RingIn;
    else if(wcnt == 3) wr3 <= RingIn;

  // Interactions with the ring
  assign RingOut     = (state == sendToken) ? 32'b0 : RingIn;
  assign SourceOut  = (state == sendToken) ? 4'b0  : SourceIn;
  assign SlotTypeOut = 
    (state == sendToken)  ? Token : 
    (SlotTypeIn == Token) ? Null : 
                            SlotTypeIn;

  always @(posedge clock) begin
    if(reset) state <= idle;
    else case(state)
      idle: if (~InhibitDDR & ~ResetDDR) state <= sendToken;
      
      sendToken: state <= waitToken;
      
      waitToken: if(SlotTypeIn == Token) begin 
        if(~InhibitDDR & ~ResetDDR) state <= sendToken;
        else state <= idle;
      end
    endcase
  end

  //cjt count the numbers of cars of each type in the train
  (* ram_style = "distributed" *)
  reg [31:0] meters[63:0];
  //there are 4 banks of 16 meters each
  //  bank 0: count types of ring slots (except for Address)
  //  bank 1: count I Address slots per core
  //  bank 2: count D/Write Address slots per core
  //  bank 3: count D/Read Address slots per core
  wire [5:0] meter_addr = (SlotTypeIn != Address) ? {2'b00,SlotTypeIn} :  // non-address, bank 0
                          (RingIn[29]) ? {2'b01,SourceIn} :  // I access, bank 1
                          {1'b1,RingIn[28],SourceIn};  // D access (W: bank 2, R: bank 3)
  always @(posedge clock) begin
    if (!reset && (state == waitToken || state == waitData)) begin
      meters[meter_addr] <= meters[meter_addr]+1;
    end
  end
  wire [31:0] meter_data = meters[{dest[7:5],rcnt}];

  //cjt multiplex in meter data when responding to reads
  reg [31:0] mdata;
  always @(*) begin
    if (dest[8]) mdata = meter_data;
    else
      case (rcnt[1:0])
        2'b00: mdata = MemData[31:0];
        2'b01: mdata = MemData[63:32];
        2'b10: mdata = MemData[95:64];
        2'b11: mdata = MemData[127:96];
      endcase
  end
  assign RDreturn = RBempty ? 32'b0 : mdata;

  //cjt change width from 5 to 9
  queueNnef #(.width(9)) destQueue(  //fifo for the read data destination
    .clk(clock),
    .din(destIn),
    .rd_en(readDest),
    .rst(reset),
    .wr_en(writeDest),
    .dout(dest)
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
    .WriteData({wr3, wr2, wr1, wr0}),

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
    .WBfull(),
    .WriteWB(writeWB),
    .WBclock(clock),
    .RBclock(clock),
    .AFclock(clock),
    .AFfull()
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
    .RD({MemData[119:96], MemData[87:64], MemData[55:32], MemData[23:0]}),
    .RDready(RDready),
    .readReq(readReq),
    .readAck(readAck),
    .RA(RA),
    .verticalFP(verticalFP),
    .displayAddress(displayAddress)
  );
endmodule