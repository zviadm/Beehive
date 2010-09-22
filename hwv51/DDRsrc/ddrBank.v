//---------------------------------------------------------------------------   
// File:        ddrBank.v
// Author:      Zhangxi Tan
// Description: Modified for 2GB dual-rank SODIMMs 
//------------------------------------------------------------------------------  

`timescale 1ns/1ps

// � Copyright Microsoft Corporation, 2008

module ddrBank(  //One I/O bank, consisting of one DQS pins and eight DQ pins and their associated logic.
 input MCLK,
 input MCLK90,
 input M90Reset,
 
//Data to/from the four ports
 input [15:0] WriteData,  //User write data
 output reg [15:0] ReadData,  //User read data (SDR)
 
//Pin signals 
 inout [7:0] DQ, //the 8 DQ pins
 inout       DQS, //the 1  DQS pin 
 inout       DQS_L,
 
//Signals to/from main FSM
 input ForceA, //force all 'A's during calibration write.	
 input StartDQCal,
 input ReadBurst, 
 input WriteBurst,  //A write is needed.
 output reg CalFail
 );

 reg M90ResetX; 
 reg [15:0] WDpipe; //pipeline for write data
 wire [15:0] RB;
 reg Force;
 reg WriteRBtime;
 reg WriteRBtimed1; //need this so that we can register allGood to fix a timing error 
 wire [7:0] laneGood;  //test of full-bank calibration
 wire       laneGoodfx;
 reg firstGood;
 reg allGood;
 reg [2:0] State; //new calibration state machine
 reg [5:0] DlyCnt;
 reg [2:0] minWin;
 reg [5:0] WS; //start of the valid window in taps
 reg [5:0] WW; //width of the window in taps.

 reg preDQSenL;
 reg resetDQdelay;
 reg incDQdelay;

//Data paths within each bank
 wire [15:0] WB;  //Write buffer
 reg ReadWB;
 reg ChangeDQS;
 reg WBd1, WBd2;

 reg Start;
 reg OddTick;
 

 //state assignments for the new calibration fsm
 localparam Idle = 3'b000;
 localparam Read1 = 3'b001;
 localparam Read2 = 3'b010;
 localparam WaitEnd = 3'b011;
 localparam DecWS = 3'b100;
 localparam DecWW = 3'b101;
 localparam FailX = 3'b110;

//-------------------End of declarations---------------------

 always@(posedge MCLK90) ReadData <= RB;
 always@(posedge MCLK90) WDpipe <= WriteData;
 always@(posedge MCLK90) Force <= ForceA; 
 assign WB = Force? 16'haaaa: WDpipe;
 always @(posedge MCLK90)begin WriteRBtime <= ReadBurst;  WriteRBtimed1 <= WriteRBtime; end
 always@(posedge MCLK90) Start <= StartDQCal;
 always@(posedge MCLK90) M90ResetX <= M90Reset;
 
 always @(posedge MCLK90) begin
    WBd1 <= WriteBurst; WBd2 <= WBd1;
  end
 always @(posedge MCLK90)  ReadWB <= WBd1 | WBd2;
 always @(posedge MCLK) ChangeDQS <= ReadWB;  
 always @(posedge MCLK) preDQSenL <= ~(WBd1 | ReadWB);
 
//Generate the DQS bits and the related logic
//the DQS pins and associated logic
   dqs_iob dqsPad0(
    .MCLK(MCLK),
    .ODDRD1(ChangeDQS),
    .ODDRD2(1'b0),
    .preDQSenL(preDQSenL),
    .DQS(DQS),
    .DQSL(DQS_L)
   );
 
 assign laneGoodfx = &laneGood;
 always @(posedge MCLK90) firstGood <= laneGoodfx;
 always @(posedge MCLK90) allGood <= firstGood & laneGoodfx; //tested during the second clock of a burst.
 
 
//Generate the 8 DQ bits and their associated read and write buffers.
 genvar dqi;
 generate
  for(dqi= 0; dqi < 8; dqi = dqi+1)
  begin: dq
  
  assign laneGood[dqi] = ~RB[2 * dqi] & RB[2 * dqi+1];
  //always @(posedge MCLK90) lgd1[dqi] <= laneGood[dqi];
  
//The I/O pin logic
   dq_iob dqx(
    .MCLK90 (MCLK90),
    .ICLK(~MCLK), 
    .Reset (M90ResetX),
    .DlyInc (incDQdelay),
    .DlyReset (resetDQdelay),
    .WbufQ0 (WB[2 * dqi]),
    .WbufQ1 (WB[2 * dqi + 1]),
    .ReadWB (ReadWB),
    .DQ (DQ[dqi]),
    .IserdesQ1 (RB[2 * dqi]),
    .IserdesQ2 (RB[2 * dqi+1])
   );
  end
 endgenerate
 
//Calibration state machine. Calibration proceeds in two phases.  During the first, the central
//control does 64 reads.  The calibrators use these to determine the delay line values for the
//start (WS) and width (WW) of the valid window.  During the second phase, all taps are reset and then
//incremented to WS + WW/2.  Because the delays are well-matched, all pins can be done in
//parallel.  The resulting window extends from the latest pin's starting delay to the earliest
//pin's end delay. 

 always @(posedge MCLK90) resetDQdelay <= (/*State == Idle & */ Start) |
                       (State == Read2 & WriteRBtimed1 & DlyCnt == 0 & minWin == 0) |
                       (State == WaitEnd);
							  
 always @(posedge MCLK90) incDQdelay <= (State == Read1 & WriteRBtimed1) | 
                     (State == Read2 & WriteRBtimed1 & (DlyCnt != 0 | minWin != 0)) |
                     (State == DecWS) |
                     (State == DecWW & WW != 0 & OddTick);

 always@(posedge MCLK90)
 begin
  if(M90ResetX)begin
   State <= Idle;

  end
  else begin
    case(State)
     Idle: if(Start) begin
       DlyCnt <= 6'd63;
       WS <= 0;
       WW <= 0;
       CalFail <= 0;
       State <= Read1;
     end
     
     Read1:   //Looking for the start of the window
      if(WriteRBtimed1) begin
        if(DlyCnt == 0) State <= FailX;
        DlyCnt <= DlyCnt - 1;
        WS <= WS + 1;
        minWin <= 3'd5;
        if(allGood) State <= Read2;
      end

     Read2:      
       if(WriteRBtimed1) begin
         DlyCnt <= DlyCnt - 1;
         if(minWin != 0) minWin <= minWin - 1;
         if(DlyCnt == 0) begin
           if(minWin == 0) State <= DecWS; //Reads ended before the end of the window, but the window we have is valid.
           else State <= FailX;  //Reads ended before a valid window found
         end
         else if(allGood) begin
           WW <= WW + 1; // In the window. Keep going.
         end
         else if(minWin != 0) State <= Read1; //Stutter at the start of the window.
           else State <= WaitEnd;  //Window ended before the last read. Normal case.
       end
      
     WaitEnd: //wait for all 64 reads to finish
       if (DlyCnt == 0) State <= DecWS;
       else if(WriteRBtimed1) DlyCnt <= DlyCnt - 1;
      
     FailX:  CalFail <= 1; //hang
     
     DecWS: begin 
      OddTick <= 0;
      if(WS == 0) State <= DecWW;
      else WS <= WS - 1;
     end
     
     DecWW: 
       if(WW == 0) State <= Idle;
       else begin
         WW <= WW - 1;
         OddTick <= ~OddTick;
       end         
    endcase
  end
 end
endmodule
