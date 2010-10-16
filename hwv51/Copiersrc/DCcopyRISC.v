
/*
This module is simplified version of the main CPU used in the block copier.

Differences are:
1) No RS232
2) No Multiplier.
3) No lock unit.
4) The data memory is a 64 word RAM, not a cache.  It can probably be removed.

*/

 (* max_fanout = "20" *) module DCcopyRISC(
 input  reset,
 input  clock,
 input  [3:0]  whichCore,  //the number of this core
 input  [31:0] RingIn,
 input  [3:0]  SlotTypeIn,
 input  [3:0]  SourceIn,
 output [31:0] msgrRingOut,
 output [3:0]  msgrSlotTypeOut,
 output [3:0]  msgrSourceOut,
 output msgrDriveRing,
 output msgrWantsToken,
 input msgrAcquireToken,
 output [31:0] wq,   //write queue output
 output loadSA,  //write strobes for registers in the DMA controller
 output loadDA,
 output loadCnt,
 input [16:0] chkBusy,
 inout DVIscl,    //Chrontel I2C
 inout DVIsda,
 input verticalFP, //from display controller
 output reg [25:0] displayAddress //to display controller

 );
 
 //signals to and from local I/O devices
 wire [31:0] rqIn;  //RISC's read queue
 wire loadOut;      //load the output register
 wire        selDmem;
 wire [31:0] rqDCache;        //data from the DCache (Data memory)
 wire        selMsgr;         //select the messenger
 wire [31:0] rqMsgr;
 reg SCLx, SDAx;

//The processor read, write, and address queues
 wire  [4:0] wrq;   //write the read queue
 wire        aqe;   //address queue empty
 wire [4:0]  done;  //read address queue
 wire [31:0] aq;   //address queue output
 wire        aqrd; //address queue entry is for a read request
 wire        wqe;  //write queue empty
 wire [4:0]  rwq;  //read the write queue
 wire wqFull;

 reg  [31:0] out;
 reg  [31:0] a, b;
 wire [31:0] ax,bx;  //The outputs of the register file
 wire [32:0] addsub; //adder/subtractor output
 wire [31:0] in;  //the ALU output (shifter input)
 wire [31:0] t1, t2;  //shifter intermediate values
 wire [4:0]  n; //the count as seen by the cycler
 wire [31:0] mask; //for shifts
 wire        fill;  //sign bit if arsh
 wire [31:0] outx;  //shifter output
 wire [31:0] amux;  //alu input
 wire [31:0] bmux;  //alu input
 wire [9:0]  pcMux;  //pcx, IM input
 reg [9:0]   pcx;  //has the address of the instruction in stage IFRR
 reg [9:0]   pc;   //pc used by EX stage
 reg [9:0]   pcd1; //pc written to link
 reg [31:0]  link;
 reg         neg, zero, cy;   //condition bits
 reg         wwq;  //write the write queue
 reg         waq;  //write the address queue
 reg         wrd;  //address queue entry is for a read request
 wire        rrq; //read from the read queue
 wire [9:0]  pcInc;  //the incremented pc
 wire        jumpOp;
 wire        doJump;  //jump actually happens
 reg         nullify;  //previous instruction was a non-nullified taken branch.
 wire        lli;   //load link immediate
 wire [31:0] instx; 
 reg  [31:0] inst;  //the instruction
 (* KEEP = "TRUE" *) wire stall;  //attempt to read from an empty read queue
 wire        noShift;  //shiftCtrl > 4
 wire [4:0] shiftAmount;  //amount to shift
 wire       left;
 wire       shift;
 wire       arith;
 
 //instruction fields
 wire [3:0] op;
 wire [2:0] funct;
 wire       const;
 wire [6:0] rb;
 wire [4:0] count;
 wire [4:0] wa;
 wire [4:0] ra;
 
 wire       rqe;  //read queue is empty
 wire [31:0] rq;  //read queue output
 wire       weRF;       //write the register file
 wire       fwdA;
 wire       fwdB;

//----------------------------------End of Declarations------------------------

/*
//instantiate the RS232.  Local I/O device 0
 assign selRS232 = ~aqe & aq[31] & (aq[2:0] == 0)& (aqrd | ~wqe);  //RS232 is local I/O device 0
  rs232noCC rs232copy(
  .clock(clock),
  .reset(reset),
  .read(aqrd),
  .wq(wq[9:0]), //don't need high order bits
  .rwq(rwq[0]),
  .rq(rqRS232),
  .wrq(wrq[0]),
  .done(done[0]),
  .selRS232(selRS232),
  .RxD(RxD),
  .TxD(TxD),
  .whichCore(whichCore)
  );
*/

//device 0 is a 1-bit read-only register that returns the value of verticalFP from the D.C.
wire selDev0 = ~aqe & aq[31] & (aq[2:0] == 0) & aqrd;
assign done[0] = selDev0;  //since we have no device 0.
assign rwq[0]  = 1'b0;
assign wrq[0]  = selDev0;

//The DMA engine is in the instantiating module. It is local I/O device 1.
wire selDMA;
assign selDMA = ~aqe & aq[31] & (aq[2:0] == 1)& (aqrd | ~wqe);
//reading the device returns the busy bit in rq[0], checksum in rq[16:1].
//writing with aq[4:3] = 0 loads SA
//writing with aq[4:1] = 1 loads DA
//writing wirh aq[4:3] = 2 loads Cnt

assign done[1] = selDMA;
assign rwq[1] = selDMA & ~aqrd;
assign wrq[1] = selDMA &  aqrd;
assign loadSA  = selDMA & ~aqrd & (aq[4:3] == 0);
assign loadDA  = selDMA & ~aqrd & (aq[4:3] == 1);
assign loadCnt = selDMA & ~aqrd & (aq[4:3] == 2);

//Pin buffers for DVIscl, DVIsda
  OBUFT sclBuf(.O(DVIscl), .I(1'b0), .T(~SCLx));
  
//(* KEEP = "TRUE" *) wire DVIsdaIn;  //to see an ACK with ChipScope
//(* KEEP = "TRUE" *) reg DVIsdaInReg;
//always @(posedge clock) DVIsdaInReg <= DVIsdaIn;

  IOBUF sdaBuf(.IO(DVIsda), .O(/*DVIsdaIn*/), .I(1'b0), .T(~SDAx));
  
 //local I/O device 2 is the Output register
 //This logic is simple enough that a separate module isn't needed.
 assign loadOut = ~aqe & ~aqrd & ~wqe & aq[31] & (aq[2:0] == 2);
 assign done[2] = loadOut;
 assign rwq[2]  = loadOut;
 assign wrq[2]  = 1'b0;
 always@(posedge clock) if (loadOut) begin
  displayAddress <= wq[27:2];
  SCLx <= wq[1];
  SDAx <= wq[0];
  
 end

//instantiate the Data Memory.  Local I/O device 3
 assign selDmem = ~aqe & ~aq[31] & (aqrd | ~wqe);  //select only when all operands are queued

  copierDataMemory dmem(
  .clock(clock),
  .aq(aq[5:0]),
  .read(aqrd),
  .wq(wq),
  .rwq(rwq[3]),
  .rqDCache(rqDCache),
  .wrq(wrq[3]),
  .done(done[3]),
  .selDCache(selDmem)
   );
  
//instantiate the messenger.  Local I/O device 4.
assign selMsgr = ~aqe & aq[31] & (aq[2:0] == 4);
  Messenger msgrN(
  .clock(clock),
  .reset(reset),
  .aq(aq[16:3]), //message type (4), payload length (6), dest core (4)
  .read(aqrd),
  .wq(wq),
  .rwq(rwq[4]),
  .rqMsgr(rqMsgr),
  .wrq(wrq[4]),
  .done(done[4]),
  .selMsgr(selMsgr),
  .whichCore(whichCore),
  .RingIn(RingIn),
  .SlotTypeIn(SlotTypeIn),
  .SourceIn(SourceIn),
  .msgrRingOut(msgrRingOut),
  .msgrSlotTypeOut(msgrSlotTypeOut),
  .msgrSourceOut(msgrSourceOut),
  .msgrDriveRing(msgrDriveRing),
  .msgrWantsToken(msgrWantsToken),
  .msgrAcquireToken(msgrAcquireToken)
  );

wire raq = | done;
  
assign rqIn = ~aq[31] ? rqDCache :   // mux for read queue input 
              (aq[2:0] == 0)? {31'b0, verticalFP} :
              (aq[2:0] == 1)? {15'b0, chkBusy} :				  
				  (aq[2:0] == 4)? rqMsgr :
				  32'b0;

//----------------------------The Processor-----------------------------------
//instruction fields
assign op = inst[3:0];
assign funct = inst[8:6];
assign const = inst[9];
assign rb = inst[16:10];
assign count = inst[21:17];
assign wa = inst[26:22];
assign ra = inst[31:27];
assign lli = op[3] & ~op[2] & ~op[1] & ~op[0]; //op == 8
assign jumpOp = op[3] & (op[2] | op[1] | op[0]);  //op > 8
assign noShift = op[3] | (op[2] & (op[1] | op[0]));  //op > 4. Disables shifting
assign left =  ~noShift & op[0]; 
assign shift = ~noShift & ~op[1];
assign arith = ~noShift &  op[2];
assign shiftAmount = noShift? 5'b0 : count;

assign stall = (((ra == 29) &  rqe) | ((wa ==31) & wqFull)) & ~lli & ~nullify;
assign rrq =   (ra == 29) & ~rqe & ~nullify;
assign pcInc = pcx + 1;
assign pcMux = doJump ? outx[9:0] : pcInc;

assign weRF = ~stall & ~nullify & ~lli & ~jumpOp;
assign fwdA = weRF & (wa == instx[31:27]);
assign fwdB = weRF & (wa == instx[14:10]);

always @(posedge clock)
  if(reset) begin
    pcx <= 0;
    pc <= 0;
    pcd1 <= 0;
    inst <= 0;
  end
  else if(~stall) begin
    pcx <= pcMux;
    pc <= pcx;
    pcd1 <= pcInc;
    inst <= instx;
	 if(fwdA) a <= outx; else a <= ax;
	 if(fwdB) b <= outx; else b <= bx;
  end

always @(posedge clock)
  if(~stall & lli & ~nullify) link <= {inst[31:4], 4'b0};  
  else if(~stall & jumpOp &~nullify) link <= {21'b0, pcd1};

always @(posedge clock) if(~stall & ~nullify & ~lli) begin
  wwq <= (wa == 31);
  waq <= (op == 6) | (op == 7) ;
  wrd <= (op == 7);  //address queue entry is a read
end else begin
  waq <= 0;
  wwq <= 0;
end

always @(posedge clock)if(reset) nullify <= 0; else nullify <= doJump;

assign doJump = ~stall & ~nullify & jumpOp & (((  ~op[1] &  op[0] & neg) |     //jump if out < 0
                ( op[1] & ~op[0] & zero) |    //jump if out == 0|
                ( op[1] &  op[0] & cy))      //jump if ALU carry out
                ^ op[2]); //op[2]) inverts the sense of all tests
					 
always @(posedge clock) out <= outx;

always @(posedge clock)
 if(~stall & ~lli & ~jumpOp & ~nullify)
 begin
    zero <= (outx == 0);
    neg <= outx[31];
	 cy <= addsub[32];
 end
 

assign amux = (ra == 31) ? {22'b0, pc} :
              (ra == 30) ? {22'b0, link} :
				  (ra == 29) ? rq :
				  a;
assign bmux = const ? {20'b0, (noShift ? count : 5'b0), rb} : b;

rom32 instMem (  // the instruction memory.
	.clka(clock),
	.addra(pcMux),
   .ena(~stall),	
	.douta(instx)); 

regFileX RFa (  //need two RAMs because there are three independent addresses
	.a(wa), //write address 
	.d(outx), 
	.dpra (instx[31:27]), //read address
	.clk(clock),
	.we(weRF),
	.spo(), 
	.dpo(ax)); 

regFileX RFb (
	.a(wa), 
	.d(outx), 
	.dpra (instx[14:10]), 
	.clk(clock),
	.we(weRF),
	.spo(), 
	.dpo(bx)); 

//A 32-bit ALU
assign in =  //in goes to the shifter
 (funct == 7) ?  amux ^ ~bmux: 
 (funct == 6) ?  amux ^  bmux:
 (funct == 5) ?  amux | ~bmux:
 (funct == 4) ?  amux |  bmux:
 (funct == 3) ?  amux & ~bmux:
 (funct == 2) ?  amux &  bmux:
 addsub[31:0];

assign addsub = {1'b0, amux} + {1'b0,(funct[0]?  ~bmux : bmux)} + funct[0];

//The ALU output goes to the shifter input
assign n = left? (32-shiftAmount)%32 : shiftAmount; //left cycle (shiftAmount) = right cycle (32 - shiftAmount)

XmaskROM masker (  //a 64 X 32 ROM.  Generates the correct mask based on shiftAmount and direction
	.a({left, shiftAmount}),  
	.spo(mask)); 

assign fill = arith & in[31];

genvar i;
generate 
for (i = 0; i < 32; i = i+1)
begin: rotblock
 assign t1[i] = (n[1] &  n[0]) ? in[(i+3)%32] :   (n[1] & ~n[0]) ? in[(i+2)%32] :  (~n[1] &  n[0]) ? in[(i+1)%32] : in[i];
 assign t2[i] = (n[3] &  n[2]) ? t1[(i+12)%32] : (n[3] & ~n[2]) ? t1[(i+8)%32] :  (~n[3] &  n[2]) ? t1[(i+4)%32] : t1[i];
 assign outx[i]  = (~shift &  ~n[4] & t2[i]) |                    //cycle
                   (~shift &   n[4] & t2[(i+16)%32]) |
                   ( shift &  mask[i] & n[4] & t2[(i+16)%32]) |  //shift, no fill
						 ( shift &  mask[i] & ~n[4] &  t2[i]) |      
					    ( shift & ~mask[i] & fill);                  //shift, do fill
end
endgenerate

//the Write, Read, and Address queues
queueN #(.width(33)) addressQueue (
	.clk(clock),
	.din({wrd, out[31:0]}),  //out[31] is I/O space 
	.rd_en(| done), //note OR reduction
	.rst(reset),
	.wr_en(waq),
	.dout({aqrd, aq}), 
	.empty(aqe),
	.full());

queueN #(.width(32)) writeQueue (
	.clk(clock),
	.din(out), 
	.rd_en(| rwq),
	.rst(reset),
	.wr_en(wwq),
	.dout(wq), 
	.empty(wqe),
	.full(wqFull));

PipedQueue32nf readQueue (
	.clk(clock),
	.din(rqIn),  
	.rd_en(rrq),
	.rst(reset),
	.wr_en(| wrq),  //note OR reduction
	.dout(rq), 
	.empty(rqe));
 
 endmodule

