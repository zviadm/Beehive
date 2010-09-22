`timescale 1ns / 1ps

// © Copyright Microsoft Corporation, 2008


(* max_fanout = 30 *) module TC5(
 input Ph0, //clock
 input ResetIn,
 output TxD, //RS232 transmit data
 input RxD,
 output reg StartDQCal0,
 output  reg [33:0] LastALU,
 output reg injectTC5address,
 input CalFailed,
 output reg InhibitDDR,
 output reg DDRclockEnable,
 output reg ResetDDR,
 output reg Force,
// output reg SDA,
// output reg SCL,
// input SDAin,
 output reg [3:0] SelectRS232,
 input ReleaseRS232,
 input Which  //TC5a or TC5b?
 );

//Event trigger signals. Two timed events and one simple event.
 reg[2:0] arm;
 reg[2:0] trig;
 reg[9:0] timer[1:0]; //only two timed triggers for now.
 reg[9:0] now; //runs continuously
 wire [2:0] xevent;
 wire [2:0] srvMask;
 wire [2:0] hev; //unary encoding of highest priority event
 wire [1:0] hpn; //binary encoding of highest priority event (only 3 events)
 wire [2:0] inh;
 wire wt; //Rw overload (Write trigger).
 wire readSR;  //Reading a character from the receiver after being triggered.
 wire [9:0] timerValue;
 reg rcvReadyd1;

//Other signals
 wire rcvReady;
 wire skI; //skip test
 wire InRdy;  //Skip condition

 reg TxDn; 
 reg [9:0] PC; //10-bit program counter
 wire [9:0] PCmux;
 wire [35:00] IM; //the Instruction memory (1K x 36) outputs 
 wire [35:00] ALU; // ALUoutput

 wire [9:0] aAddr; //register file port a read address
 wire [9:0] bAddr; //register file port b read address 
 wire [9:0] wAddr; //register file write address

wire [35:00] zPCinc; //zero-extended PC + 1
wire doSkip;
wire [35:00] WD; //write data to the register file
wire [35:00] RFAout; //register file port A read data
wire [35:00] RFBout; //register file port B read data
wire [9:0]   PCinc, PCinc2;
wire [35:00] ALUresult;
wire OutStrobe; //internally used register overload
wire Jump; //Opcode decodes

wire [7:0] rcvData; //from rs232rcv to TC4 indata
wire [35:00] InData; // I/O input -- some bits used for flags.
reg CalFail;

//----------End of declarations------------

//Event triggers
 assign inh[0] = trig[0];
 assign hev[0] = trig[0];
 genvar i; //fixed priority encoder.  Zero is highest.
 generate
   for(i = 1; i < 3; i = i + 1)
   begin: priblock
     assign hev[i] = trig[i] & ~inh[i-1];
     assign inh[i] = trig[i] | inh[i-1];     
   end
 endgenerate
 assign srvMask = (InRdy & skI)? hev: 3'b0; //unary mask of the trigger that will be serviced
 assign hpn[0] = hev[1]; //binary encoding of high priority trigger
 assign hpn[1] = hev[2];
 always @(posedge Ph0) now <= now + 1; //counter runs continuously
 
 always @(posedge Ph0) if(~DDRclockEnable) trig <= 3'b0;
   else trig <= (xevent & arm) | (trig & ~srvMask);
 always @(posedge Ph0) if(wt) begin
   arm[LastALU[1:0]] <= LastALU[2]; //rearm or disarm
   if(LastALU[1:0] < 2) timer[LastALU[0]] <= ALU[9:0]; // if this is a timed trigger, reload it
 end
 assign xevent[0] = timer[0] == now;
 assign xevent[1] = timer[1] == now;
 assign xevent[2] = rcvReady & ~rcvReadyd1;
 assign InRdy = | trig;  //Skip condition
 assign skI = IM[3:2] == 3;
 assign timerValue = LastALU[1:0] < 2 ? timer[LastALU[0]]: now;
 
 assign InData = {10'b0,rcvData[7:0], 3'b0, Which, 2'b0, 
   CalFail, hpn[1], skI? hpn[0]: timerValue[9], timerValue[8:0]};

 //we know when the program is reading a character because it uses the && InData
 //function with an 8-bit mask in the high halfword.
 assign readSR = IM[9:7] == 3 & RFAout[18];
 always@(posedge Ph0) rcvReadyd1 <= rcvReady;
 
// Main TC5
 always @(posedge Ph0) CalFail <= CalFailed;
 always @(posedge Ph0) if(ResetIn) PC <= 0; else PC <= PCmux;
 always @(posedge Ph0) if(IM[1:0] != 3) LastALU <= ALU[33:0];  //don't load on Jumps
 
//The Skip tester.
 assign doSkip = ~ResetIn & (((~IM[3] &  IM[2] & ALU[35]) |       //skip on ALU < 0
                ( IM[3] & ~IM[2] & (ALU == 0)) |    //skip on ALU == 0|
                ( IM[3] &  IM[2] & InRdy))          //skip on InRdy
                ^IM[4]); //msb inverts the sense of all tests
 
//RW overloads
 assign OutStrobe     = IM[35:28] == 8'd255;
 assign wt            = IM[35:28] == 8'd254;
 always @(posedge Ph0) injectTC5address <= IM[35:28] == 8'd253;


//Opcode decode.
 assign Jump  = IM[1] &  IM[0] & ~ResetIn;

// The WD multiplexer. It is controlled solely by the Op field.
 assign zPCinc = {26'b0, PCinc[9:0]};
 assign WD = Jump? zPCinc: ALU;


//The PC-derived signals
 assign PCinc =  PC + 1;
 assign PCinc2 = PC + 2;
 assign PCmux = Jump? ALU[9:0]: doSkip ? PCinc2: PCinc;
 
//The IM. Read during Ph == 0.

 dpbram36 im(
 .wda(36'b0), //port A is the write port.
 .aa(10'b0),
 .wea(1'b0),
 .ena(1'b0),
 .clka(1'b0),
 .rdb(IM), //port B is the read port.
 .wdb(36'b0),
 .ab(PCmux[9:0]),
 .web(1'b0),
 .enb(1'b1),
 .clkb(Ph0)
 );
  
 assign aAddr = IM[1:0] == 1? {1'b0, LastALU[8:0]}: {1'b0, IM[27:19]}; 
 assign bAddr = {1'b0 , IM[18:10]}; 
 assign wAddr = IM[1:0] == 2? {1'b0, LastALU[8:0]}: {2'b0, IM[35:28]}; 
   
//The register file.  This has three independent addresses, so two BRAMs are needed.
// Read after the read and write addresses are stable (fall of Ph0).
// Written at the end of the instruction).
 dpbram36 rfA(
  .rda(),
  .wda(WD), //port A is the write port.
  .aa(wAddr),
  .wea(1'b1),
  .ena(1'b1),
  .clka(Ph0),
  .rdb(RFAout), // port B is the read port A.
  .wdb(36'b0),
  .ab(aAddr),
  .web(1'b0),
  .enb(1'b1),
  .clkb(~Ph0)
  );
  
 dpbram36 rfB(
 .rda(),
 .wda(WD), //port A is the write port.
 .aa(wAddr),
 .wea(1'b1),
 .ena(1'b1),
 .clka(Ph0),
 .rdb(RFBout), //port B is the read port B.
 .wdb(36'b0),
 .ab(bAddr),
 .web(1'b0),
 .enb(1'b1),
 .clkb(~Ph0)
 );

//The ALU: An adder/subtractor followed by a shifter
 assign ALUresult =
               IM[9:7] == 7 ?  RFAout & ~RFBout: 
               IM[9:7] == 6 ?  RFAout ^ RFBout:
               IM[9:7] == 5 ?  RFAout | ~RFBout:
               IM[9:7] == 4 ?  RFAout | RFBout:
               IM[9:7] == 3 ?  RFAout & InData:
               IM[9:7] == 2 ?  RFAout & RFBout:
               RFAout + (IM[7]?  ~RFBout: RFBout) + IM[7];
                    
//generate the shifter one bit at a time
 genvar j;
 generate
  for(j = 0; j < 36; j = j+1)
   begin: shblock
    assign ALU[j] = //36 LUTs.  Cycler
     (~IM[6] & ~IM[5] & ALUresult[j]) | //0: no cycle
     (~IM[6] &  IM[5] & ALUresult[(j + 1)  % 36]) | //1: rcy 1
     ( IM[6] & ~IM[5] & ALUresult[(j + 9)  % 36]) | //2: rcy 9
     ( IM[6] &  IM[5] & ALUresult[(j + 18) % 36]) ; //3: rcy 18
   end //shblock
 endgenerate

 
//instantiate the RS232 receiver
rs232rcv receiver(
    .Ph0(Ph0),
    .RxD(RxD),
    .rData(rcvData),//received character
    .ready(rcvReady),
    .readSR(readSR)
  );    

 //Outputs
 always @(posedge Ph0)  if (OutStrobe) begin
  StartDQCal0 <= ALU[0];
  InhibitDDR <= ALU[1];
  DDRclockEnable <= ALU[2];
  ResetDDR <= ALU[3];
//  SDA <= ALU[5];
//  SCL <= ALU[6];
  Force <= ALU[7];
  TxDn <= ALU[9];
 end
 
 always @(posedge Ph0) if (ResetIn | ReleaseRS232) SelectRS232 <= 0;
   else if(OutStrobe & (ALU[21:18] != 0)) SelectRS232 <= ALU[21:18];
 
assign TxD = ~TxDn;
 
endmodule
