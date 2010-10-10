`timescale 1ns / 1ps
`default_nettype none

(* max_fanout = "30" *) module RISCtop(
  input CLKBN,
  input CLKBP,

  //Signals to the DIMMs
  inout [63:0] DQ, //the 72 DQ pins
  inout [7:0] DQS, //the 18  DQS pins
  inout [7:0] DQS_L,
  output [1:0] DIMMCK,  //differential clock to the DIMM
  output [1:0] DIMMCKL,
  output [13:0] A, //addresses to DIMMs
  output [2:0] BA, //bank address to DIMMs
  output [7:0] DM, //masks to DIMMs
  output [1:0] RS, //rank select
  output RAS,
  output CAS,
  output WE,
  output [1:0] ODT,
  output [1:0] ClkEn, //common clock enable for both DIMMs. SSTL1_8

  input FPGAreset, //low true
  inout SCL,  //I2C clock
  inout SDA,  //I2C data
  output TxD, //RS232 transmit data
  input RxD,  //RS232 received data

  //GMII signals 
  output   [7:0]  GMII_TXD_0,
  output          GMII_TX_EN_0,
  output          GMII_TX_ER_0,
  output          GMII_TX_CLK_0, //to PHY. Made in ODDR
  input    [7:0]  GMII_RXD_0,
  input           GMII_RX_DV_0,
  input           GMII_RX_CLK_0 , //from PHY. Goes through BUFG
  output          GMII_RESET_B,
  output   [7:0]  LED,

  output [11:0] DVIdata, //Display controller signals
  output DVIclkP,
  output DVIclkN,
  output DVIhsync,
  output DVIvsync,
  output DVIde, //data enable
  output DVIresetB, //low true DVIreset
  //DVI I2C
  inout DVIscl,  //clock
  inout DVIsda   //data
);
 
  parameter nCores = 13;  //Number of RISC cores in the design
  parameter EtherCore = nCores + 1;
  parameter CopyCore  = nCores + 2;
  
  //Clocks
  wire clockIn;
  wire MCLK; 
  wire MCLK90;
  wire Ph0;
  wire clock;
  wire clockx;
  wire clock90;
  wire clock90x;
  wire ethTXclock;
  wire MCLKx;
  wire MCLK90x;
  wire Ph0x;
  wire ethTXclockx;
  wire PLLBfb;
  wire pllLock;
  wire ctrlLock;
  wire reset;
  wire [3:0] SelRS232;  //from TC5

  //The registers of the ring
  reg [31:0] RingOut[0:nCores + 2];
  reg [3:0] SlotTypeOut[0:nCores + 2];
  reg [3:0] SourceOut[0:nCores + 2];

  reg [31:0] RDreturn[0:nCores];  //separate pipelined bus for read data
  reg [3:0] RDdest[0:nCores];
 
  wire[nCores + 1:1] releaseRS232;
  // wire[nCores : 1]   lockHeld;
  wire[nCores + 1:0]  TxDv; 
  wire[nCores + 1:0] RxDv;
 
  wire SCLx;
  wire SDAx;
  wire SDAin;
  wire verticalFP;
  wire [25:0] displayAddress;
 
//-----------------------------End of Declarations-----------------------------


//instantiate the RISC cores
genvar i;
generate
  for (i = 1; i <= nCores; i = i+1)
  begin: coreBlk
    wire [31:0] tempRiscRingOut;
    wire [3:0] tempRiscSlotTypeOut;
    wire [3:0] tempRiscSourceOut;
    wire [3:0] coreNum;

    assign coreNum = i;

    RISC riscN(
      .reset(reset),
      .clock(clock),
      .whichCore(coreNum),  //the number of this core
      .CopyCore(CopyCore),
      .EtherCore(EtherCore),
      .RingIn(RingOut[i-1]),
      .SlotTypeIn(SlotTypeOut[i-1]),
      .SourceIn(SourceOut[i-1]),
      .RDreturn(RDreturn[i-1]),
      .RDdest(RDdest[i-1]),
      .RingOut(tempRiscRingOut),
      .SlotTypeOut(tempRiscSlotTypeOut),
      .SourceOut(tempRiscSourceOut),
      .RxD(RxDv[i]),
      .TxD(TxDv[i]),
      //core connected to the RS232 pulses this to reset 
      //the selection back to the TC5
      .releaseRS232(releaseRS232[i])
      //  .lockHeld(lockHeld[i])
    );
    always @(posedge clock) begin
      RDreturn[i] <= RDreturn[i-1];
      RDdest[i] <= RDdest[i-1];
    end

    always @(posedge clock) begin
      RingOut[i] <= tempRiscRingOut;
      SlotTypeOut[i] <= tempRiscSlotTypeOut;
      SourceOut[i] <= tempRiscSourceOut;
    end
  end
endgenerate

  wire [31:0] tempMCtrlRingOut;
  wire [3:0]  tempMCtrlSlotTypeOut;
  wire [3:0]  tempMCtrlSourceOut;
  wire [31:0] tempMCtrlRDreturn;
  wire [3:0]  tempMCtrlRDdest;
 
  //Instantiate the memory controller (contains the display controller)
  defparam mctrl.mmsFSM.nCores = nCores;
  CoherentMemMux mctrl(
    .clock(clock),
    .clock90(clock90),
    .reset(reset),

    .RingIn(RingOut[nCores + 2]),
    .SlotTypeIn(SlotTypeOut[nCores + 2]),
    .SourceIn(SourceOut[nCores + 2]),
    .RingOut(tempMCtrlRingOut),
    .SlotTypeOut(tempMCtrlSlotTypeOut),
    .SourceOut(tempMCtrlSourceOut),
    .RDreturn(tempMCtrlRDreturn),
    .RDdest(tempMCtrlRDdest),

    .DQ(DQ),
    .DQS(DQS),
    .DQS_L(DQS_L),
    .DIMMCK(DIMMCK),
    .DIMMCKL(DIMMCKL),
    .A(A),
    .BA(BA),
    .RS(RS),
    .RAS(RAS),
    .CAS(CAS),
    .WE(WE),
    .ODT(ODT),
    .DM(DM),
    .ClkEn(ClkEn),
    .MCLK(MCLK),
    .MCLK90(MCLK90),
    .Ph0(Ph0),
    .TxD(TxDv[0]),
    .RxD(RxDv[0]),
    .SelectRS232(SelRS232),
    .ReleaseRS232( |releaseRS232),
    .LED(LED),
    .DVIdata(DVIdata),
    .DVIclkP(DVIclkP),
    .DVIclkN(DVIclkN),
    .DVIhsync(DVIhsync),
    .DVIvsync(DVIvsync),
    .DVIde(DVIde),
    .DVIresetB(DVIresetB),
    .verticalFP(verticalFP),
    .displayAddress(displayAddress)
  );

  always@(posedge clock) begin
    RDreturn[0] <= tempMCtrlRDreturn;
    RDdest[0] <= tempMCtrlRDdest;
  end
 
  always@(posedge clock) begin
    RingOut[0] <= tempMCtrlRingOut;
    SlotTypeOut[0] <= tempMCtrlSlotTypeOut;
    SourceOut[0] <= tempMCtrlSourceOut;
  end

  //Instantiate the Ethernet Controller
  wire [31:0] tempEthconRingOut;
  wire [3:0]  tempEthconSlotTypeOut;
  wire [3:0]  tempEthconSourceOut;

  Ethernet ethcon( 
    .reset(reset),
    .ethTXclock(ethTXclock),  //125 MHz 50% duty cycle clock
    .clock(clock),            //100 MHz clock
    .whichCore(EtherCore),    //the number of 
    .CopyCore(CopyCore),

    //Ring signals
    .RingIn(RingOut[nCores]),
    .SlotTypeIn(SlotTypeOut[nCores]),
    .SourceIn(SourceOut[nCores]),
    .RingOut(tempEthconRingOut),
    .SlotTypeOut(tempEthconSlotTypeOut),
    .SourceOut(tempEthconSourceOut),
    .RDreturn(RDreturn[nCores]),
    .RDdest(RDdest[nCores]),

    //RS232 signals
    .RxD(RxDv[nCores + 1]),
    .TxD(TxDv[nCores + 1]),
    .releaseRS232(releaseRS232[nCores + 1]),
    .SDAx(SDAx),
    .SCLx(SCLx),
    .SDAin(SDAin),

    //GMII interface
    .GMII_TXD_0(GMII_TXD_0),
    .GMII_TX_EN_0(GMII_TX_EN_0),
    .GMII_TX_ER_0(GMII_TX_ER_0),
    .GMII_TX_CLK_0(GMII_TX_CLK_0), //to PHY. Made in ODDR
    .GMII_RXD_0(GMII_RXD_0),
    .GMII_RX_DV_0(GMII_RX_DV_0),
    .GMII_RX_CLK_0(GMII_RX_CLK_0) , //from PHY. Goes through BUFG
    .GMII_RESET_B(GMII_RESET_B)
  );

  always@(posedge clock) begin
    RingOut[nCores + 1] <= tempEthconRingOut;
    SlotTypeOut[nCores + 1] <= tempEthconSlotTypeOut;
    SourceOut[nCores + 1] <= tempEthconSourceOut;
  end

  //Instantiate the block copier
  wire [31:0] tempBCopyRingOut;
  wire [3:0]  tempBCopySlotTypeOut;
  wire [3:0]  tempBCopySourceOut;

  copier bcopy( 
    .reset(reset),
    .clock(clock), //100 MHz clock
    .whichCore(CopyCore),  //the number of the core
 
    //Ring signals
    .RingIn(RingOut[nCores + 1]),
    .SlotTypeIn(SlotTypeOut[nCores + 1]),
    .SourceIn(SourceOut[nCores + 1]),
    .RingOut(tempBCopyRingOut),
    .SlotTypeOut(tempBCopySlotTypeOut),
    .SourceOut(tempBCopySourceOut),
     //Copier gets RDreturn data without waiting for the ring.
    .RDreturn(RDreturn[0]), 
    .RDdest(RDdest[0]),
    .DVIscl(DVIscl),
    .DVIsda(DVIsda),
    .verticalFP(verticalFP),
    .displayAddress(displayAddress)
  );

  always@(posedge clock) begin
    RingOut[nCores + 2] <= tempBCopyRingOut;
    SlotTypeOut[nCores + 2] <= tempBCopySlotTypeOut;
    SourceOut[nCores + 2] <= tempBCopySourceOut;
  end
  
  //Pin buffers for SDA, SCL used by the Ethernet controller
  OBUFT sclBuf(.O(SCL), .I(1'b0), .T(~SCLx));
  IOBUF sdaBuf(.IO(SDA), .O(SDAin), .I(1'b0), .T(~SDAx));


  //Pins for RxD and TXD
  assign TxD = TxDv[SelRS232];

genvar j;
generate
  for(j = 0; j <= nCores + 1; j = j+1)
  begin: rsblock
    assign RxDv[j] = (SelRS232 == j) ? RxD : 1'b1;
  end
endgenerate
                  
  //Reset and the clocks
 
  /*
    reg [27:0] rCnt; //reset the system every 10 seconds
    reg rcntz;
      always @(posedge Ph0) rcntz <= rCnt == 0;
      always @(posedge Ph0) rCnt <= rCnt + 1;

      assign reset = ~FPGAreset  | ~pllLock | ~ctrlLock | rcntz ;
  */
  assign reset = ~FPGAreset  | ~pllLock | ~ctrlLock;
  
  (* DIFF_TERM = "TRUE" *) IBUFGDS ClkBuf (
    .O (clockIn),
    .I (CLKBP),
    .IB (CLKBN)
  );
    
  //PLL for clocks
  PLL_BASE #(
    .BANDWIDTH("OPTIMIZED"), // "HIGH", "LOW" or "OPTIMIZED"
    .CLKFBOUT_MULT(20),  //1 GHz
    .CLKFBOUT_PHASE(0.0), 
    .CLKIN_PERIOD(5.0), 
    .CLKOUT0_DIVIDE(5), //MCLK: 200 MHz
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0.0),
    .CLKOUT1_DIVIDE(5), //MCLK90: 200 MHz, 90 degree shift
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(90.0), 
    .CLKOUT2_DIVIDE(20), //Ph0: 50 MHz
    .CLKOUT2_DUTY_CYCLE(0.375),
    .CLKOUT2_PHASE(0.0), 
    .CLKOUT3_DIVIDE(10), //clock: 100 MHz, 50% duty cycle
    .CLKOUT3_DUTY_CYCLE(0.5), 
    .CLKOUT3_PHASE(0.0), 
    .CLKOUT4_DIVIDE(8), //125 MHz
    .CLKOUT4_DUTY_CYCLE(0.5),
    .CLKOUT4_PHASE(0.0),
    .CLKOUT5_DIVIDE(10),//clock90: 100 MHz 50% duty cycle 90 degree phase shift
    .CLKOUT5_DUTY_CYCLE(0.5),
    .CLKOUT5_PHASE(90.0), 
    .COMPENSATION("SYSTEM_SYNCHRONOUS"), // "SYSTEM_SYNCHRONOUS",
    .DIVCLK_DIVIDE(4), // Division factor for all clocks (1 to 52)
    .REF_JITTER(0.100) // Input reference jitter (0.000 to 0.999 UI%)
  ) clkBPLL (
    .CLKFBOUT(PLLBfb), // General output feedback signal
    .CLKOUT0(MCLKx), // 
    .CLKOUT1(MCLK90x),
    .CLKOUT2(Ph0x),
    .CLKOUT3(clockx),
    .CLKOUT4(ethTXclockx),
    .CLKOUT5(clock90x),
    .LOCKED(pllLock), // Active high PLL lock signal
    .CLKFBIN(PLLBfb), // Clock feedback input
    .CLKIN(clockIn), // Clock input
    .RST(1'b0)
  );

  BUFG bufC (.O(clock), .I(clockx));
  BUFG bufC90 (.O(clock90), .I(clock90x));
  BUFG bufM (.O(MCLK), .I(MCLKx));
  BUFG bufM90 (.O(MCLK90), .I(MCLK90x));
  BUFG p0buf(.O(Ph0), .I(Ph0x));
  BUFG CKbuf(.O(ethTXclock), .I(ethTXclockx));
 
  //instantiate an idelayctrl.
  IDELAYCTRL idelayctrl0 (
    .RDY(ctrlLock),
    .REFCLK(MCLK), 
    .RST(~pllLock)
  );
endmodule
