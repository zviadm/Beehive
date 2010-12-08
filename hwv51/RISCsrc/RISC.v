`timescale 1ns / 1ps

/*
This module is a 32-bit RISC processor and its local I/O system.

The local I/O devices include a 32 x 32 2's complement multiplier,
an RS232 interface to a console terminal, a D-cache for the CPU,
an interface to a message-passing facility, and a unit that supports 
atomic operations.

It is a node on the interprocessor ring interconnect,
and may be instantiated several times on a single chip.
*/

// bitTime = 868 => 115Kbaud for serial link
// I_INIT => filename used to initialize icache during simulation
// D_INIT => filename used to initialize dcache during simulation
(* max_fanout = "20" *) module RISC #(parameter bitTime = 868, 
                                                I_INIT="NONE",
                                                D_INIT="NONE") (
  input  reset,
  input  clock,
  input  [3:0]  whichCore,  //the number of this core  
  input  [31:0] RingIn,
  input  [3:0]  SlotTypeIn,
  input  [3:0]  SourceIn,
  input  [31:0] RDreturn,
  input  [3:0]  RDdest,
  output [31:0] RingOut,
  output [3:0]  SlotTypeOut,
  output [3:0]  SourceOut,
  input  RxD,
  output TxD,
  output reg    releaseRS232
  // output  lockHeld
);
   
  //signals to and from local I/O devices
  wire [31:0] rqIn;  //RISC's read queue
  
  // Multiplier and RS232
  wire        selRS232;
  wire        selMul;
  wire [31:0] rqRS232; //the RS232 data
  wire [31:0] rqMul; //the multiplier result
  
  // I/DCache Unit
  wire        selDCache;
  wire        selDCacheIO;
  wire [31:0] rqDCache;  //data from the cache
  wire [31:0] dcRingOut;
  wire [3:0]  dcSlotTypeOut;
  wire [3:0]  dcSourceOut;
  wire        dcDriveRing;
  wire        dcWantsToken;
  wire        dcAcquireToken;
  
  // Messenger Unit
  wire        selMsgr;
  wire [31:0] rqMsgr;
  wire [31:0] msgrRingOut;
  wire [3:0]  msgrSlotTypeOut;
  wire [3:0]  msgrSourceOut;
  wire        msgrDriveRing;
  wire        msgrWantsToken;
  wire        msgrAcquireToken;
  
  // Lock Unit
  wire        selLock;
  wire [31:0] rqLock;
  wire [31:0] lockRingOut;
  wire [3:0]  lockSlotTypeOut;
  wire [3:0]  lockSourceOut;
  wire        lockDriveRing;
  wire        lockWantsToken;
  wire        lockAcquireToken;
  
  // Barrier Unit
  wire        selBarrier;
  wire [31:0] barrierRingOut;
  wire [3:0]  barrierSlotTypeOut;
  wire [3:0]  barrierSourceOut; 
  wire        barrierDriveRing;
  wire        barrierWantsToken;
  wire        barrierAcquireToken;
 
  //The processor read, write, and address queues
  wire  [5:0] wrq;   //write the read queue
  wire        aqe;   //address queue empty
  wire [6:0]  done;  //read address queue
  wire [31:0] aq;   //address queue output
  wire        aqrd; //address queue entry is for a read request
  wire        wqe;  //write queue empty
  wire [4:0]  rwq;  //read the write queue
  wire [31:0] wq;   //write queue output
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
  wire [30:0] pcMux;  //pcx, IM input
  reg [30:0]  pcx;  //has the address of the instruction in stage IFRR
  reg [30:0]  pc;   //pc used by EX stage
  reg [30:0]  pcd1; //pc written to link
  reg [31:0]  link;
  wire [31:0] linkIn;
  wire doLoadLink;
  reg         neg, zero, cy;   //condition bits
  reg         wwq;  //write the write queue
  reg         waq;  //write the address queue
  reg         wrd;  //address queue entry is for a read request
  wire        rrq; //read from the read queue
  wire [30:0] pcInc;  //the incremented pc
  wire        jumpOp;
  wire        doJump;  //jump actually happens
  reg         nullify; //previous instruction was a non-nullified taken branch.
  wire        lli;   //load link immediate
  wire [31:0] instx; 
  reg  [31:0] inst;  //the instruction
  (* KEEP = "TRUE" *) wire stall; //attempt to read from an empty read queue
  wire        noShift;  //shiftCtrl > 4
  wire [4:0]  shiftAmount;  //amount to shift
  wire        left;
  wire        shift;
  wire        arith;

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
  wire       Ihit;
  wire       decLineAddr;
  (* KEEP = "TRUE" *) reg [9:0] stallCnt; //for testing
 
  wire       ctrlValid;  //debugging unit signals
  wire [3:0] ctrlType;
  wire [3:0] ctrlSrc;
  wire       j7valid;
  wire       loadLink;
  wire [31:0] linkValue;
  wire       zeroPCsetNullify;
  wire       emptyAWqueues;
  (* KEEP = "TRUE" *) wire stopOK;
  wire [3:0] nextOp;

//-----------------------------End of Declarations-----------------------------
  assign nextOp = instx[3:0];
  assign stopOK = (op <= 5) & ~lli & aqe & wqe & ~stall & 
                  ~nullify & (nextOp < 8) & (nextOp != 3) ;
 
  DebugUnit debugger(
    .clock(clock),
    .reset(reset),
    .link(link),
    .PC(pc),
    .whichCore(whichCore),
    //(~stall & ~nullify & (op == 15) & wa[4]),  //enable operations
    .j7valid(j7valid),  
    //from rb[2:0]
    .opcode(rb[2:0]),  

    //read queue is empty
    .rqe(rqe),       
    //control message information from the Messenger
    .ctrlValid(ctrlValid), 
    .ctrlSrc(ctrlSrc),
    .ctrlType(ctrlType),

    .loadLink(loadLink),
    .linkValue(linkValue),
    .zeroPCsetNullify(zeroPCsetNullify),
    .emptyAWqueues(emptyAWqueues),
    .stopOK(stopOK)
  );

  always @(posedge clock) 
    if (stall) stallCnt <= stallCnt + 1; 
    else stallCnt <= 0;

  //instantiate the RS232.  Local I/O device 0
  //RS232 is local I/O device 0
  assign selRS232 = ~aqe & aq[31] & (aq[2:0] == 0)& (aqrd | ~wqe);  

  rs232 #(.bitTime(bitTime)) rs232x(
    .clock(clock),
    .reset(reset),
    .read(aqrd),
    .wq(wq[9:0]), //don't need high order bits
    .rwq(rwq[0]),
    .rq(rqRS232),
    .wrq(wrq[0]),
    .done(done[0]),
    .selRS232(selRS232),
    .a3(aq[3]),
    .RxD(RxD),
    .TxD(TxD),
    .whichCore(whichCore)
  );


  //instantiate the multiplier. Local I/O device 1
  //multiplier is local IO device 1.
  assign selMul = ~aqe & aq[31] & (aq[2:0] == 1); 
  //Note that we assume that the operands are already in wq.

  mul mulUnit(
    .clock(clock),
    .reset(reset),
    .wq(wq),
    .rwq(rwq[1]),
    .rq(rqMul),
    .wrq(wrq[1]),
    .done(done[1]),
    .selMul(selMul)
  );

  //local I/O device 2 is the Output register, which has only one bit so far.
  //This logic is simple enough that a separate module isn't needed.
  wire loadOut = ~aqe & ~aqrd & ~wqe & aq[31] & (aq[2:0] == 2);
  assign done[2] = loadOut;
  assign rwq[2]  = loadOut;
  assign wrq[2]  = 1'b0;
  always@(posedge clock) if (loadOut) begin
    //lockHeld <= wq[1];
    releaseRS232 <= wq[0];
  end

  //instantiate the I/DCache.  Local I/O device 3
  //select only when all operands are queued
  assign selDCache = ~aqe & ~aq[31] & (aqrd | ~wqe);  
  assign selDCacheIO = ~aqe & aq[31] & aq[2:0] == 3;
 
  CoherentDCache #(.I_INIT(I_INIT),.D_INIT(D_INIT)) dCacheN(
  //DCache #(.I_INIT(I_INIT),.D_INIT(D_INIT)) dCacheN(
    .clock(clock),
    .reset(reset),
    .aq(aq[30:0]),
    .read(aqrd),
    .wq(wq),
    .rwq(rwq[3]),
    .rqDCache(rqDCache),
    .wrq(wrq[3]),
    .done(done[3]),
    .selDCache(selDCache),
    .selDCacheIO(selDCacheIO),
    .decLineAddr(decLineAddr),
    
    .whichCore(whichCore),
    
    //Ring Signals
    .RingIn(RingIn),
    .SlotTypeIn(SlotTypeIn),
    .SourceIn(SourceIn),
    .dcRingOut(dcRingOut),
    .dcSlotTypeOut(dcSlotTypeOut),
    .dcSourceOut(dcSourceOut),
    .dcDriveRing(dcDriveRing),
    .dcWantsToken(dcWantsToken),
    .dcAcquireToken(dcAcquireToken),
    
    //Signals for ICache operation
    .pcMux(pcMux[8:0]),
    .pcx(pcx),
    .stall(stall),
    .instx(instx),
    .Ihit(Ihit),
    
    //RDreturn ring
    .RDreturn(RDreturn),
    .RDdest(RDdest)
  );
  
  //instantiate the messenger.  Local I/O device 4.
  assign selMsgr = ~aqe & aq[31] & (aq[2:0] == 4);

  Messenger msgrN(
    .clock(clock),
    .reset(reset),
    .aq(aq[16:3]), //other aq bits not used
    .read(aqrd),
    .wq(wq),
    .rwq(rwq[4]),
    .rqMsgr(rqMsgr),
    .wrq(wrq[4]),
    .done(done[4]),
    .selMsgr(selMsgr),
    .whichCore(whichCore),
    
    //Ring Signals
    .RingIn(RingIn),
    .SlotTypeIn(SlotTypeIn),
    .SourceIn(SourceIn),
    .msgrRingOut(msgrRingOut),
    .msgrSlotTypeOut(msgrSlotTypeOut),
    .msgrSourceOut(msgrSourceOut),
    .msgrDriveRing(msgrDriveRing),
    .msgrWantsToken(msgrWantsToken),
    .msgrAcquireToken(msgrAcquireToken),
    
    //Ctrl Signals for Debugging Unit
    .ctrlValid(ctrlValid),
    .ctrlType(ctrlType),
    .ctrlSrc(ctrlSrc)
  );

  //instantiate the sem unit.  Local I/O device 5.
  assign selLock = ~aqe & aq[31] & (aq[2:0] == 5);
  Sem lockUnit(
    .clock(clock),
    .reset(reset),
    .aq(aq[8:3]), //other aq bits not used
    .read(aqrd),
    .rqLock(rqLock),
    .wrq(wrq[5]),
    .done(done[5]),
    .selLock(selLock),
    .whichCore(whichCore),
    
    //Ring Signals
    .RingIn(RingIn),
    .SlotTypeIn(SlotTypeIn),
    .SourceIn(SourceIn),
    .lockRingOut(lockRingOut),
    .lockSlotTypeOut(lockSlotTypeOut),
    .lockSourceOut(lockSourceOut),
    .lockDriveRing(lockDriveRing),
    .lockWantsToken(lockWantsToken),
    .lockAcquireToken(lockAcquireToken)
  );
  
  //instantiate the barrier unit.  Local I/O device 6.
  assign selBarrier = ~aqe & aq[31] & (aq[2:0] == 6);

  Barrier BarrierUnit(
    .clock(clock),
    .reset(reset),
    .done(done[6]),
    .selBarrier(selBarrier),
    .whichCore(whichCore),
    
    //Ring Signals
    .RingIn(RingIn),
    .SlotTypeIn(SlotTypeIn),
    .SourceIn(SourceIn),
    .barrierRingOut(barrierRingOut),
    .barrierSlotTypeOut(barrierSlotTypeOut),
    .barrierSourceOut(barrierSourceOut),
    .barrierDriveRing(barrierDriveRing),
    .barrierWantsToken(barrierWantsToken),
    .barrierAcquireToken(barrierAcquireToken)
  );
    
  wire raq = | done;
  
  // mux for read queue input 
  assign rqIn = ~aq[31] ? rqDCache       :   
                (aq[2:0] == 0)? rqRS232  : 
                (aq[2:0] == 1)? rqMul    :
                (aq[2:0] == 3)? rqDCache :
                (aq[2:0] == 4)? rqMsgr   :
                (aq[2:0] == 5)? rqLock   :
                32'b0;

  //State Machine that handles Interactions with the ring
  reg state;
  localparam idle = 0;  
  localparam tokenHeld = 1;
  
  wire coreHasToken = (SlotTypeIn == `Token);// | (state == tokenHeld);  
  wire coreSendNewToken = 
    ((coreHasToken | (state == tokenHeld)) & 
     ~msgrDriveRing & ~lockDriveRing & ~barrierDriveRing & ~dcDriveRing);

  assign msgrAcquireToken = 
    (coreHasToken & msgrWantsToken);
  assign lockAcquireToken = 
    (coreHasToken & ~msgrWantsToken & lockWantsToken);
  assign barrierAcquireToken = 
    (coreHasToken & ~msgrWantsToken & ~lockWantsToken & barrierWantsToken);
  assign dcAcquireToken = 
    (coreHasToken & ~msgrWantsToken & ~lockWantsToken & ~barrierWantsToken & 
     dcWantsToken);

  always @(posedge clock) begin
    if(reset) state <= idle;
    else case(state)
      idle: if(SlotTypeIn == `Token) begin
        if (msgrWantsToken | lockWantsToken | barrierWantsToken | dcWantsToken)
          state <= tokenHeld;
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
  
  assign RingOut = msgrDriveRing    ? msgrRingOut    :
                   lockDriveRing    ? lockRingOut    :
                   barrierDriveRing ? barrierRingOut :
                   dcDriveRing      ? dcRingOut      :
                   coreDriveRing    ? coreRingOut    :
                   RingIn;

  assign SlotTypeOut = msgrDriveRing    ? msgrSlotTypeOut    :
                       lockDriveRing    ? lockSlotTypeOut    :
                       barrierDriveRing ? barrierSlotTypeOut :
                       dcDriveRing      ? dcSlotTypeOut      :
                       coreDriveRing    ? coreSlotTypeOut    :
                       SlotTypeIn;

  assign SourceOut = msgrDriveRing    ? msgrSourceOut    :
                     lockDriveRing    ? lockSourceOut    :
                     barrierDriveRing ? barrierSourceOut :
                     dcDriveRing      ? dcSourceOut      :
                     coreDriveRing    ? coreSourceOut    :
                     SourceIn;
 
//----------------------------The Processor-----------------------------------
  //instruction fields
  assign op = inst[3:0];
  assign funct = inst[8:6];
  assign const = inst[9];
  assign rb = inst[16:10];
  assign count = inst[21:17];
  assign wa = inst[26:22];
  assign ra = inst[31:27];

  assign lli = (op == 3);

  assign jumpOp = (op >= 8);

  assign noShift = (op > 4);

  assign left =  ~noShift & op[0];  //1 or 3 
  assign shift = ~noShift & ~op[1]; //0 or 1
  assign arith = ~noShift &  op[2]; //4
  assign shiftAmount = noShift? 5'b0 : count;

  assign stall = 
    ((((ra == 29) &  rqe) | ((wa == 31) & wqFull)) & ~lli & ~nullify) | ~Ihit;

  assign rrq =   (ra == 29) & ~rqe & ~nullify & ~stall;
  assign pcInc = pcx + 1;
  // modified by cjt: make pcMux be *exactly* what will be loaded into pcx.
  // this will make the Icache much happier during cache hits while stalled!
  assign pcMux = (reset | zeroPCsetNullify) ? 0 :
                 stall ? pcx :
                 doJump ? outx[30:0] : pcInc;

  assign weRF = ~stall & ~nullify & ~lli & ~jumpOp & (wa != 0);
  assign fwdA = weRF & (wa == instx[31:27]);
  assign fwdB = weRF & (wa == instx[14:10]);

  assign j7valid = ~stall & ~nullify & (op == 15) & wa[4];

  always @(posedge clock)
    if(reset) begin
      pc <= 0;
      pcd1 <= 0;
      inst <= 0;
    end
    else if(~stall) begin
      pc <= pcx;
      pcd1 <= pcInc;
      inst <= instx;
      if(fwdA) a <= outx; else a <= ax;
      if(fwdB) b <= outx; else b <= bx;
    end
  
  always @(posedge clock) pcx <= pcMux;
  
  assign doLoadLink = ~stall & ~nullify &
    (lli |
     (op == 8) |
     ((wa == 30) & ~lli & ~jumpOp) |
     loadLink);

  assign linkIn = 
    lli ? {inst[31:4], 4'b0} :  //lli
    (op == 8) ? {1'b0, pcd1} :  //call  
    ((wa == 30) & ~lli & ~jumpOp) ? outx : //Rw override
    linkValue; //debug unit
  
  always @(posedge clock) if(doLoadLink) link <= linkIn;

  always @(posedge clock) if(~stall & ~nullify & ~lli) begin
    wwq <= (wa == 31);
    waq <= (op == 6) | (op == 7) ;
    wrd <= (op == 7);  //address queue entry is a read
  end else begin
    waq <= 0;
    wwq <= 0;
  end

  always @(posedge clock)
    if (reset) nullify <= 0; 
    else if (Ihit) nullify <= doJump | zeroPCsetNullify;

  wire class0jmp;
  //wire class1jmp; no class1 jumps yet.  Just j7, which isn't a jump
  assign class0jmp = ~wa[4] &
    ((op == 8) |  //call
     (op[3] &
      ((~op[1] &  op[0] & neg) |     //jump if out < 0
       ( op[1] & ~op[0] & zero) |    //jump if out == 0|
       ( op[1] &  op[0] & cy)        //jump if ALU carry out
      ) ^ op[2] //op[2] inverts the sense of <, ==, carry
     )
    );

  /*When we add class 1 jump 0..6, they will go here.
  assign class1jmp = wa[4] &
    (

    );
  */

  assign doJump = ~stall & ~nullify & jumpOp &  class0jmp;
  //(class0jmp | class1jmp);

  always @(posedge clock) out <= outx;

  always @(posedge clock)
    if(~stall & ~lli & ~jumpOp & ~nullify)
    begin
      zero <= (outx == 0);
      neg <= outx[31];
      cy <= addsub[32];
    end
 

  assign amux = (ra == 31) ? {1'b0, pc} :
                (ra == 30) ? link :
                (ra == 29) ? rq :
                a;

  assign bmux = ~const ? b :
    { (jumpOp ? {16'b0, wa[3:0]} : 20'b0), (noShift ? count : 5'b0), rb};

  //need two RAMs because there are three independent addresses
  regFileX RFa (  
    .a(wa), //write address 
    .d(outx), 
    .dpra(instx[31:27]), //read address
    .clk(clock),
    .we(weRF),
    .spo(), 
    .dpo(ax)
  ); 

  regFileX RFb (
    .a(wa), 
    .d(outx), 
    .dpra(instx[14:10]), 
    .clk(clock),
    .we(weRF),
    .spo(), 
    .dpo(bx)
  ); 

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
  //left cycle (shiftAmount) = right cycle (32 - shiftAmount)
  assign n = left ? (32-shiftAmount)%32 : shiftAmount;

  //a 64 X 32 ROM.  Generates the correct mask based on 
  //shiftAmount and direction
  XmaskROM masker (  
    .a({left, shiftAmount}),  
    .spo(mask)
  ); 

  assign fill = arith & in[31];

genvar i;
generate 
  for (i = 0; i < 32; i = i+1)
  begin: rotblock
    assign t1[i] = (n[1] &  n[0]) ? in[(i+3)%32] :   
                   (n[1] & ~n[0]) ? in[(i+2)%32] :  
                   (~n[1] & n[0]) ? in[(i+1)%32] : in[i];
    assign t2[i] = (n[3] &  n[2]) ? t1[(i+12)%32] : 
                   (n[3] & ~n[2]) ? t1[(i+8)%32] :  
                   (~n[3] &  n[2]) ? t1[(i+4)%32] : t1[i];
    assign outx[i] = 
      (~shift &   ~n[4] & t2[i]) |                //cycle
      (~shift &    n[4] & t2[(i+16)%32]) |
      ( shift & mask[i] & n[4] & t2[(i+16)%32]) | //shift, no fill
      ( shift &  mask[i] & ~n[4] &  t2[i]) |      
      ( shift & ~mask[i] & fill);                 //shift, do fill
  end
endgenerate

  //the Write, Read, and Address queues
  PipedAddressQueue addressQueue (
    .clk(clock),
    .din({wrd, out[1:0], out[31:2]}), 
    .rd_en(| done), //note OR reduction
    .rst(reset | emptyAWqueues),
    .wr_en(waq),
    .dout({aqrd, aq}), 
    .empty(aqe),
    .decLineAddr(decLineAddr)
  );

  queueN #(.width(32)) writeQueue (
    .clk(clock),
    .din(out), 
    .rd_en(| rwq),
    .rst(reset | emptyAWqueues),
    .wr_en(wwq),
    .dout(wq), 
    .empty(wqe),
    .full(wqFull)
  );

  PipedQueue32nf readQueue (
    .clk(clock),
    .din(rqIn),  
    .rd_en(rrq),
    .rst(reset),
    .wr_en(| wrq),  //note OR reduction
    .dout(rq), 
    .empty(rqe)
  );
 
endmodule
