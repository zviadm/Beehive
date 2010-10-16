//---------------------------------------------------------------------------   
// File:        ddrController.v
// Author:      Zhangxi Tan
// Description: Modified for 2GB dual-rank SODIMMs 
//------------------------------------------------------------------------------  

`timescale 1ns / 1ps

//  Copyright Microsoft Corporation, 2008

 module ddrController(

 input CLK, //Clocks
 input MCLK,
 input MCLK90,

//User logic interface
 input [25:0] Address,		//only lower 26 bits are used (for the 2GB address space)
 input Read, //1 = Read, 0 = Write
 input WriteAF,
 output reg AFfull,  //can't do anything if full
 input AFclock,
 
 output [127:0] ReadData,
 input ReadRB,
 output RBempty,
 output RBfull,
 input RBclock,
 output SingleError,
 output DoubleError,

 input  [127:0]  WriteData,
 input WriteWB,
 output WBfull, //can't write if full
 input WBclock,
 
 //Signals to/from the DIMMs
 inout [63:0] DQ, //the 64 DQ pins
 inout [7:0] DQS, //the 8 DQS pins
 inout [7:0] DQS_L,
 output [1:0] DIMMCK,  //differential clock to the DIMM
 output [1:0] DIMMCKL,
 output [13:0] A, //addresses to DIMMs
 output [2:0] BA, //bank address to DIMMs
 output [7:0] DM, //data mask
 output [1:0] RS, //rank select
 output RAS,
 output CAS,
 output WE,
 output [1:0] ODT,
 output [1:0] ClkEn, //common clock enable for both DIMMs. SSTL1_8

//Signals to/from the TC5
 input StartDQCal0, //start the I/O bank-specific FSMs
 input [33:0] LastALU,  //from TC5 (only bits [33:0] are used)
 input injectTC5address,
 input InhibitDDR,
 input Force,
 input ResetDDR,
 input Reset,

 output reg CalFailed,
 input DDRclockEnable
 );
 wire WriteAFpipe;
 reg [26:0] AFpipe;
 reg AFpipeValid;
 
 //wire WBempty;
 wire AFempty; 
 wire AFfullx;
 
 (* syn_keep = 1 *) wire GetNext;
 wire [127:0] WD; //data to I/O banks
 wire [127:0] RD; //DDR data from I/O banks

 wire [26:0]  AD;     //address and command from AF
 wire [7:0]   DMx;    //wires to DMs
 
 reg Inhibit;
 reg Force0;
 reg ForceN90;
 reg Force90;
 wire StartOp;
 reg StartDQCal;
 wire [1:0] preClk; //DIMM clocks
  
//ODT-related signals
 reg odtd1, odtd2, odtd3, odtd4;
 reg odtOut;
 
 wire [13:0]rowIn;   //14 bits: 16K rows
 wire [2:0] bankIn;  //3 bits: 8 banks
 wire [7:0] colIn;   //8 bits: 1K columns/row, each access gets 4 columns
 wire       rankIn;  //1 bit: The DIMM, rank within a DIMM
 wire [2:0] numOps;  //numOps from bank logic for the requested rank (unary).
 
 reg wd0, /*wd1,*/ wd2, wd3, wd4; //WriteBurst delay 
 reg WriteBurst;
 reg WBd1, ReadWB;
 
 reg rd0, /*rd1,*/ rd2, rd3, rd4, rd5, rd6, rd7, rd8, rd9, rd10, rd11, rd12, rd13;
 reg ReadBurst;
 reg WriteRB;

 reg State; //the main FSM
 wire [1:0] RankDecode;

 wire [7:0] Fail; //CalFail from each bank
 reg FailX; // | Fail, clocked by MCLK90.
 wire [1:0] LoadTact, LoadTread, LoadTwrite, LoadTref;
 
 reg CReset;
 reg MReset;
 reg M90NReset;
 reg M90Reset;
 
//signals involved in ensuring timing specs
 reg[3:0] Tlr; //time since last read
 reg[3:0] Tlw; //time since the last write
 reg[3:0] Tlp; //time since the last precharge
 reg TlpZ, TlwZ, TlrZ; //register is zero
 wire Stall;

 reg[3:0] Tact[1:0]; //time since last act for each of the two ranks. Counts down, 
//loaded with tXX when operation is issued, sticks at (and initialized to) 0.
 reg[3:0] Tread[1:0]; //time since last read
 reg[3:0] Twrite[1:0]; //time since last write
 reg[5:0] Tref[1:0]; //time since the last refresh
 reg [1:0] TrefZ, TwriteZ, TreadZ, TactZ;
 
//Address and control signals to the DIMMS
 reg [2:0] cmd; //the command register (RAS, CAS, WE)
 reg [2:0] cmdd1;
 reg [2:0] cmdd2;
 reg r_ras, r_cas, r_we;
 reg [2:0] altCmd;
 reg [13:0] addr; 
 reg [9:2] altAddr; //the alternate address
 reg [13:0] addrd1;
 reg [13:0] addrd2;
 reg [2:0] bank; //the bank number
 reg [2:0] bankd1;
 reg [2:0] bankd2;
 reg       rank;
 reg [1:0] rankd1;
 reg [1:0] rankd2;
 
 reg StartDQCal1;
 reg inject1;
 

 reg       clk_ce_l, clk_ce;
 wire	   r_Inhibit;
//main state assignment
 localparam Idle = 0;
 localparam Act = 1;
 
 //command encoding 
 localparam ReadCmd = 3'b101;
 localparam WriteCmd = 3'b100;
 localparam PrechargeCmd = 3'b010;
 localparam NopCmd = 3'b111;
 localparam ActiveCmd = 3'b011;
 localparam RefreshCmd = 3'b001;
 
//timing limits
localparam tRPA =  3;  //3; //precharge all period (15ns + tCK = 5 MCLK
localparam tWTR =  5;  //5; //write-to-read (10 MCLK)
localparam tRTW =  2;  //2; //read-to-write (4 MCLK)
localparam tRTP =  3; //read-to-precharge (7.5ns, 2 MCLK)
localparam tWTP =  6;  //6; //write-to-precharge (12 MCLK)
localparam tRAS =  6;  //6; //act-to-precharge (40ns, 11 MCLK)
localparam tRFC = 17;  //17;  //refresh-to-act (127.5ns, 34 MCLK)

localparam tFAW = 5;   //4-bank open limit


reg [tFAW-1:0]  faw_win[0:1];

reg [2:0]       act_cnt[0:1];

reg [1:0]      stall_act;
wire [1:0]      new_act;

reg RBfulld1;

//--------------------End of declarations---------------------------
 assign DMx = 8'h0;
 always @(posedge CLK) RBfulld1 <= RBfull;
 always @(posedge CLK) Inhibit <= InhibitDDR | RBfulld1; //stop when RB fills.
 // always @(posedge CLK) Inhibit <= InhibitDDR | RBfull; //stop when RB fills.
 
 always @(posedge CLK) Force0 <= Force;
 always @(negedge MCLK90) ForceN90 <= Force0;
 always @(posedge MCLK90) Force90 <= ForceN90;
 
 always @(posedge MCLK90) FailX <= | Fail;
 always @(posedge CLK) CalFailed <= FailX;
 always @(posedge CLK) inject1 <= injectTC5address;

 always @(posedge CLK) CReset <= Reset | ResetDDR; 
 always @(posedge MCLK) MReset <= CReset;
 always @(negedge MCLK90) M90NReset <= MReset;
 always @(posedge MCLK90)M90Reset <= M90NReset;
 
 always @(negedge MCLK90) StartDQCal1 <= StartDQCal0;
 always @(posedge MCLK90) StartDQCal <= StartDQCal1;
 
 genvar clkp; //clocks to the DIMMs
 generate
  for(clkp = 0; clkp < 2; clkp = clkp +1)
  begin: clkpin

 ODDR #(.SRTYPE("SYNC"),.DDR_CLK_EDGE("SAME_EDGE"))  oddr_clk (
    .Q (preClk[clkp]),
    .C (MCLK),
    .CE (1'b1),
    .D1 (1'b0),  //DIMMCK = MCLK180
    .D2 (1'b1),
    .R (1'b0),
    .S (1'b0)
  ); 
 OBUFDS  dimmcbuf (
     .O (DIMMCK[clkp]),
     .OB (DIMMCKL[clkp]),
     .I (preClk[clkp])
  );
  end
 endgenerate
 
//writeBurst delay chain 
 always @(negedge MCLK90) wd0 <= (cmdd1 == WriteCmd);
 always @(posedge MCLK90) begin  
    //wd1 <= wd0;   //registered DIMM
    wd2 <= wd0; wd3 <= wd2; wd4 <= wd3; WriteBurst <= wd4;
    WBd1 <= WriteBurst; ReadWB <= (WriteBurst | WBd1) & ~Force90;
 end
 

//readBurst delay chain  
 always @(negedge MCLK90) rd0 <= cmdd1 == ReadCmd;
 always @(posedge MCLK90) begin 
    //rd1 <= rd0;  //registered DIMM
    rd2 <= rd0; rd3 <= rd2; rd4 <= rd3;
    rd5 <= rd4; rd6 <= rd5; rd7 <= rd6; rd8 <= rd7; rd9 <= rd8; rd10 <= rd9;
    rd11 <= rd10; rd12 <= rd11;
    ReadBurst <= rd12; rd13 <= ReadBurst; 
    WriteRB <= (ReadBurst | rd13) & ~Force90;
  end
 

//The xxxd1 pins allow signals to the DIMM to go into the output pins
 always @(negedge MCLK)  clk_ce_l <= CLK;
 always @(posedge MCLK)  clk_ce <= ~clk_ce_l;
 
 always @(posedge MCLK) //cmdd1
   if(clk_ce) cmdd1 <= cmd;
   else cmdd1 <= altCmd;

 always @(posedge MCLK) //addrd1
   if(clk_ce) addrd1 <= addr;
   else addrd1 <= {4'b0000, altAddr, 2'b00};
      
 always @(posedge MCLK) begin
   rankd1 <= rank == 0? 2'b10: 2'b01;
   rankd2 <= rankd1;
   bankd1 <= bank;
   bankd2 <= bankd1;
   addrd2 <= addrd1;
   cmdd2 <= cmdd1;

   r_we <= cmdd1[0];
   r_cas <= cmdd1[1];
   r_ras <= cmdd1[2];
 end


//Instantiate the Address FIFO
 AF addrFifo(.WD({Read, Address[25:0]}),
   .WEn(WriteAF), .WriteClk(AFclock), .Full(AFfullx),
   .RD(AD), .Empty(AFempty),
   .REn(WriteAFpipe),
   .RDClk(CLK),
   .Reset(CReset)
 );


 dpram rInhibit(.CLK(CLK), .in(Inhibit), .out(r_Inhibit), .ra(5'b0), .wa(5'b0), .we(1'b1));
 
// always @(posedge RBclock) r_Inhibit <= Inhibit;				//add one pipe for better timing
 always @(posedge AFclock) AFfull <= r_Inhibit | AFfullx;

 assign WriteAFpipe = ~AFempty & ~Inhibit & (~AFpipeValid | GetNext);
 
 always @(posedge CLK) begin 
  if (CReset)
    AFpipeValid <= 1'b0;
  else
    AFpipeValid <= WriteAFpipe | (AFpipeValid & ~GetNext);
 end

 
 always @(posedge CLK) if(WriteAFpipe) AFpipe <= AD;


 wire ReadCommand = AFpipe[26]; 
 assign rankIn = AFpipe[25];    //2 bits
 assign rowIn  = AFpipe[24:11]; //14 bits
 assign bankIn = AFpipe[10:8]; //3 bits
 assign colIn  = AFpipe[7:0];   //8 bits
 
 genvar outpin;
 generate
  for(outpin = 0; outpin < 14; outpin = outpin + 1)
  begin: outpinx
    if(outpin < 3) OBUF bankPin(.I(bankd2[outpin]), .O(BA[outpin]));
    if(outpin < 2) OBUF rankPin(.I(rankd2[outpin]), .O(RS[outpin]));
    if(outpin < 2) OBUF ckeBuf (.I(DDRclockEnable), .O(ClkEn[outpin]));
    if(outpin < 8) OBUF dmPin(.I(DMx[outpin]), .O(DM[outpin]));
    OBUF addrPin(.I(addrd2[outpin]), .O(A[outpin]));
  end
 endgenerate

/*
  OBUF rasPin (.I(cmdd2[0]), .O(WE));
  OBUF casPin (.I(cmdd2[1]), .O(CAS));
  OBUF wePin  (.I(cmdd2[2]), .O(RAS));
*/

  OBUF wePin (.I(r_we), .O(WE));
  OBUF casPin (.I(r_cas), .O(CAS));
  OBUF rasPin  (.I(r_ras), .O(RAS));
 
//ODT timing chain
/*  always @(posedge MCLK) begin
   odtd0 <= cmdd1 == ReadCmd;
   odtd1 <= cmdd1 == WriteCmd | odtd0;
   odtd2 <= odtd1;
   odtd3 <= odtd2;
   odtd4 <= odtd3;
   odtd5 <= odtd4;
   odtOut <= odtd3 | odtd4 | odtd5;
  end
*/

  always @(posedge MCLK) begin
   odtd1 <= cmdd2 == WriteCmd;
//   odtd1 <= '0;		
   odtd2 <= odtd1;
   odtd3 <= odtd2;
   odtd4 <= odtd3;
   odtOut <= odtd2 | odtd3 | odtd4;
  end
  
  OBUF odt0Pin(.I(odtOut), .O(ODT[0]));
  OBUF odt1Pin(.I(odtOut), .O(ODT[1]));  
  

//Timing limit enforcemt
 always @(posedge CLK)
   if(CReset) begin Tlr <= 0; TlrZ <= 1; end
   else if((StartOp & ReadCommand) | (State == Act &  ReadCommand)) begin 
     Tlr <= tRTW; 
     TlrZ <= 0; 
   end
   else if(Tlr != 0) begin if(Tlr == 1) TlrZ <= 1; Tlr <= Tlr - 1; end

 always @(posedge CLK)
   if(CReset) begin Tlw <= 0; TlwZ <= 1; end
   else if((StartOp & ~ReadCommand) | (State == Act &  ~ReadCommand)) begin 
     Tlw <= tWTR;
     TlwZ <= 0;
   end
   else if( Tlw != 0) begin if (Tlw == 1) TlwZ <= 1; Tlw <= Tlw - 1; end

 always @(posedge CLK)
   if(CReset) begin Tlp <= 0; TlpZ <= 1; end
   else if( StartOp& (numOps[2] )) begin
     Tlp <= tRPA;
     TlpZ <= 0;
   end
   else if( Tlp != 0) begin if(Tlp == 1) TlpZ <= 1; Tlp <= Tlp - 1; end
  

 assign Stall = (~TlwZ & ReadCommand)  |   //Write to read
                (~TlrZ & ~ReadCommand) |   //Read to write
                (~TactZ[rankIn]   & numOps[2]) |
                (~TwriteZ[rankIn] & numOps[2]) |
                (~TreadZ[rankIn]  & numOps[2]) |
                ~TrefZ[rankIn] | stall_act[rankIn] | Inhibit;                
                
 assign RankDecode = rankIn == 0? 2'b01 : 2'b10;
                
 assign LoadTact   = (StartOp & numOps[1]) | State == Act ? RankDecode : 2'b0 ;
 assign LoadTread  = (StartOp &  ReadCommand) | (State == Act &  ReadCommand) ? RankDecode : 2'b0;
 assign LoadTwrite = (StartOp & ~ReadCommand) | (State == Act & ~ReadCommand) ? RankDecode : 2'b0;
 assign LoadTref   = injectTC5address & ~inject1?
   LastALU[26] == 0? 2'b01 : 2'b10 : 2'b00;


//Generate two copies (one per rank) of Tact, Tread, Twrite, Tref, and the associated TxxZ bits.
 genvar timeCnt;
 generate
   for (timeCnt = 0; timeCnt < 2; timeCnt = timeCnt + 1)
   begin: timex

    assign new_act[timeCnt] = (StartOp & numOps[1]) | ((State == Act) & ~(~TlpZ | cmd == PrechargeCmd) & ~Inhibit & TrefZ[timeCnt] & ~stall_act[timeCnt]);
    
    always @(posedge CLK) begin
       if (CReset) begin
        act_cnt[timeCnt]   <=  0;
        stall_act[timeCnt] <= 0;
       end
       else begin
        case ({new_act[timeCnt], faw_win[timeCnt][0]})
         2'b00 : act_cnt[timeCnt]  <= act_cnt[timeCnt];
         2'b01 : begin act_cnt[timeCnt]  <= act_cnt[timeCnt] - 1; stall_act[timeCnt] <= 0; end
         2'b10 : begin act_cnt[timeCnt]  <= act_cnt[timeCnt] + 1; stall_act[timeCnt] <= (act_cnt[timeCnt]==3); end
         2'b11 : act_cnt[timeCnt]  <= act_cnt[timeCnt];
        endcase
        end
        faw_win[timeCnt] <= {new_act[timeCnt], faw_win[timeCnt][tFAW-1:1]};    
    end

      
     always@(posedge CLK)
       if(CReset) begin Tact[timeCnt] <= 0; TactZ[timeCnt] <= 1; end
       else if(LoadTact[timeCnt]) begin 
         Tact[timeCnt] <= tRAS;
         TactZ[timeCnt] <= 0;
       end
       else if (Tact[timeCnt] != 0) begin
         if(Tact[timeCnt] == 1) TactZ[timeCnt] <= 1;
         Tact[timeCnt] <= Tact[timeCnt] - 1;
       end

     always@(posedge CLK)
       if(CReset) begin 
         Tread[timeCnt] <= 0; TreadZ[timeCnt] <= 1; end
       else if(LoadTread[timeCnt]) begin 
         Tread[timeCnt] <= tRTP; 
         TreadZ[timeCnt] <= 0; 
       end
       else if (Tread[timeCnt] != 0) begin
         if(Tread[timeCnt] == 1) TreadZ[timeCnt] <= 1;
         Tread[timeCnt] <= Tread[timeCnt] - 1;
       end
 
     always@(posedge CLK)
       if(CReset) begin Twrite[timeCnt] <= 0; TwriteZ[timeCnt] <= 1; end
       else if(LoadTwrite[timeCnt]) begin 
         Twrite[timeCnt] <= tWTP; 
         TwriteZ[timeCnt] <= 0; 
       end
       else if (Twrite[timeCnt] !=0) begin
         if(Twrite[timeCnt] == 1) TwriteZ[timeCnt] <= 1;
         Twrite[timeCnt] <= Twrite[timeCnt] - 1;
       end

     always@(posedge CLK)
       if(CReset) begin Tref[timeCnt] <= 0; TrefZ[timeCnt] <= 1; end
       else if(LoadTref[timeCnt]) begin 
         Tref[timeCnt] <= tRFC; 
         TrefZ[timeCnt] <= 0; 
       end
       else if (Tref[timeCnt] !=0) begin
         if(Tref[timeCnt] == 1) TrefZ[timeCnt] <= 1;
         Tref[timeCnt] <= Tref[timeCnt] - 1;
       end
  end
 endgenerate

assign StartOp = AFpipeValid & (State == Idle) & ~Stall;
assign GetNext = (StartOp & ~numOps[2]) | ((State == Act) & TlpZ & ~Inhibit & TrefZ[rankIn] & ~stall_act[rankIn]);

 obLogic OB(
  .CLK(CLK),
  .Reset(CReset),
  .doReset(cmd == RefreshCmd),
  .row (AD[24:11]),
  .bank (AD[10:8]),
  .rank (AD[25]),
  .refRank (rank),
  .doOp(WriteAFpipe),
  .redoValid(AFpipeValid),
//  .doOp(ob_doOp),
  .numOps(numOps)
 );

//Instantiate the read and write buffers

 WB writeBuf( .Reset(CReset), .WD(WriteData), .WRen(WriteWB), .WRclk(WBclock), .Full(WBfull),
   .MD(WD), .Rclk(MCLK90), .RDen(ReadWB), .Empty(/*WBempty*/));
   
 RB readBuf( .Reset(CReset), .MD(RD), .WRen(WriteRB), .WRclk(MCLK90), .Full(RBfull),
   .RD(ReadData), .Rclk(RBclock), .RDen(ReadRB), .SingleError(SingleError), .DoubleError(DoubleError), .Empty(RBempty));
   
//Instantiate the I/O bank-specific logic 
 genvar dimmBank;
  generate
   for(dimmBank = 0; dimmBank < 8; dimmBank = dimmBank + 1)
   begin: bankx
   
      ddrBank ddrBankx(
       .MCLK (MCLK),
       .MCLK90 (MCLK90),
       .M90Reset (M90Reset),
       .WriteData (WD[16 * dimmBank +: 16]),
       .ReadData(RD[16 * dimmBank +: 16]),
       .DQ (DQ [8 * dimmBank +: 8]),  //the 8 DQ pins.
       .DQS (DQS[dimmBank]),  //the DQS pins.
       .DQS_L (DQS_L[dimmBank]),
       .StartDQCal (StartDQCal),
       .ReadBurst(ReadBurst),
       .WriteBurst (WriteBurst),  //From control logic, indicating that a write is coming.
       .CalFail (Fail[dimmBank]),
       .ForceA(Force90)
      );
     end
 endgenerate
   
//The main FSM
  always @(posedge CLK)
    if(CReset) begin
     cmd <= NopCmd;
     altCmd <= NopCmd;
     State <= Idle;
   end
   
   else begin 
   if(injectTC5address & ~inject1) begin  //differentiate injectTC5address
       altAddr <= LastALU[7:0];   //col address
       bank <= LastALU[11:9];			
       addr <= LastALU[25:12];        		//row address
       rank <= LastALU[26];
       cmd <=  LastALU[30:28];
       altCmd <= LastALU[33:31];
   end

   
   else begin
     
   case(State)  
   Idle:	begin			    //reuse the same bit definition in the TC5 program, but treat some don't care
     if (StartOp) begin
       rank <= rankIn;
       if(numOps[0]) begin  //Hit.  Issue Nop, Op
           cmd <= NopCmd;
           altCmd <= ReadCommand? ReadCmd: WriteCmd;
           altAddr <= colIn[7:0];    //col address
           bank <= bankIn;
           State <= Idle;
       end
       else if(numOps[1]) begin //Miss, no conflict. Issue Act, Op.
       //the read that follows it one MCLK later uses a column address.
           cmd <= ActiveCmd;
           altCmd <= ReadCommand? ReadCmd: WriteCmd;
           addr <= rowIn;
           altAddr <= colIn[7:0];
           bank <= bankIn;
           State <= Idle;
       end
       else begin //Conflict. Issue Precharge, Nop, goto Act
           cmd <= PrechargeCmd;
           altCmd <= NopCmd;
           bank <= bankIn;
           addr[10] <= 0;  //Single bank Precharge.
           addr[9:0] <= 10'bxxxxxxxxxx;
           addr[13:11] <= 3'bxxx;
           State <= Act;
       end
      end //if(StartOp)
      else begin
        cmd <= NopCmd;
        addr <= 14'bxxxxxxxxxxxxxx;        
        altCmd <= NopCmd;
        altAddr <= 8'bxxxxxxxx;
        bank <= bankIn; 
        State <= Idle;
    end //case (Idle)
   end 
   Act: begin //We just issued a Precharge.  Wait for TlpZ == 0, issue Act, Op, goto Idle.
      rank <= rankIn;
      if(~TlpZ | Inhibit | ~TrefZ[rankIn] | stall_act[rankIn]) begin
        cmd <= NopCmd;
        altCmd <= NopCmd;
        bank <= bankIn;
        addr <= 14'bxxxxxxxxxxxxxx;        
        altAddr <= 8'bxxxxxxxx;
      end
      else begin
        cmd <= ActiveCmd; //Issue Act, Op
        altCmd <= ReadCommand? ReadCmd: WriteCmd;
        addr <= rowIn;
        altAddr <= colIn[7:0];
        bank <= bankIn;
        State <= Idle;
      end            
    end
  endcase //case State
end
end
endmodule
