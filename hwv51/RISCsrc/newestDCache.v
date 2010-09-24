`timescale 1ns / 1ps

module newestDCache #(parameter I_INIT="NONE",D_INIT="NONE") (
  //signals common to all local I/O devices:
  input clock, 
  input reset,
  input [30:0] aq, //the CPU address queue output.  Bit 31 not used
  input read,      //request in AQ is a read
  input [31:0] wq, //the CPU write queue output
  output rwq,      //read the write queue
  output [31:0] rqDCache, //the CPU read queue input
  output wrq,      //write the read queue
  output done,     //operation is finished. 
                   //Read the AQ, read WQ if operation was write
  input selDCache,
  input selDCacheIO, //invalidate or flush operation
  input [3:0] whichCore,
  
  //ring signals
  input  [31:0] RingIn,
  input  [3:0] SlotTypeIn,
  input  [3:0] SrcDestIn,
 
  //addition for separate read data return ring.
  //cache never modifies the data or dest, so there are no outputs
  input [31:0] RDreturn,
  input [3:0] RDdest,
 
  output [31:0] dcRingOut,
  output [3:0] dcSlotTypeOut,
  output [3:0] dcSrcDestOut,
  output dcDriveRing,
 
  //instruction cache signals
  input [9:0] pcMux,
  input [30:0] pcx,
  input stall,
  output [31:0] instx,
  output Ihit,
  output decLineAddr,
  input msgrWaiting,
  input lockerWaiting,
  input barrierWaiting
);
 
  wire[21:0] Dtag;  //output of data tag memory
  wire[21:0] DtagIn; //D input of data tag memory
  wire Dhit;
  wire Ddirty;    //data cache line is dirty
  wire Dinvalid;  //data cache line is invalid
  reg [2:0] cnt;  //counts word transfers to and from DDR2
  wire incCnt;    //time to increment cnt
  wire [2:0] cacheAddr;
  reg [7:0] burstLength;  //length of the burst following a token
  reg [3:0] state;  //state machine
  // reg[31:0] memData; //data from memory
  wire[31:0] cacheData; //output of dataCache memory
  wire writeDtag;
  wire writeDdata;
  reg select;
  reg [7:0] lineCnt;   //selects the line during flushes and invalidates

  wire[20:0] Itag;
  reg writeItag;
  reg Dmiss;  //are we servicing a D or an I miss?
  wire [9:0] Iaddr;
  wire preWriteItag;
  reg  flushing;


  parameter idle = 0;  //states
  parameter waitToken = 1;  //wait for a token
  parameter waitN = 2;      //Wait for the last slot of the burst
  parameter readCache = 3;  //Send dirty miss data
  parameter sendWA = 4;     //Send write address
  parameter sendRA = 5;     //Send read address
  parameter waitRD = 6;      //Wait for read data 
  parameter readData = 7;       //Write read data into cache
  parameter preIdle = 8;
  parameter doInvalidate = 9;
  parameter doFlush = 10;

  parameter Null = 7; //Slot Types
  parameter Token = 1;
  parameter Address = 2;
  parameter WriteData = 3;
  parameter ReadData = 4;
 
//---------------------------------End of Declarations-------------------------


  assign Iaddr = Ihit? pcMux[9:0] : pcx[9:0];

  assign DtagIn = 
    //write while idle makes the line dirty
    (state == idle)? {1'b1, aq[30:10]} :  
    //refill on a miss cleans the line 
    ((state != idle) & ~selDCacheIO) ? {1'b0, aq[30:10]} : 
    //Flush or invalidate leaves address alone but cleans the line
    {1'b0, Dtag[20:0]};  


generate
  if (I_INIT == "NONE") begin : icache_synth
    dpbram32 instCache (
      .rda(instx),      //the instruction
      .wda(32'b0),
      .aa(Iaddr),  
      .wea(1'b0),    //write enable 
      .ena(~stall | ~Ihit),
      .clka(clock),
      .rdb(),
      .wdb(RDreturn),      //the data from memory 
      .ab({pcx[9:3], cacheAddr}),     //line address , cnt 
      .web(~Dmiss & (RDdest == whichCore)),     //write enable 
      .enb(1'b1),
      .clkb(clock)
    );
  end
  else begin : icache_sim
    reg [31:0] instCache[1023:0];
    reg [9:0] instAddr;
    always @(posedge clock) begin
      if (~stall | ~Ihit) instAddr <= Iaddr;  // sync read for BRAM	
      if (~Dmiss & (RDdest == whichCore))
        instCache[{pcx[9:3], cacheAddr}] <= RDreturn;
    end
    assign instx = instCache[instAddr];

    initial $readmemh(I_INIT,instCache);
  end
endgenerate
 
  tagmemX dataTag (
    .a(aq[9:3]), // Bus [6 : 0] 
    .d(DtagIn),
    .clk(clock),
    .we(writeDtag),
    .spo(Dtag)
  );

  dValidTag dataInvalid (
    .a(aq[9:3]), // Bus [6 : 0] 
    .d(state == doInvalidate),  
    .clk(clock),
    .we(writeDtag),
    .spo(Dinvalid)
  );

  itagmemX instTag (
    .a(pcx[9:3]), 
    .d(pcx[30:10]),
    .clk(clock),
    .we(writeItag),
    .spo(Itag)
  ); 

generate
  if (D_INIT == "NONE") begin : dcache_synth
    dpbram32 #(.INIT_FILE(D_INIT)) dataCache (
      .rda(rqDCache),         //the input of the read queue
      .wda(wq),         //the output of the write queue 
      .aa(aq[9:0]),     //address with the low bits of the address queue 
      .wea(writeDdata),    //write enable 
      .ena(1'b1),
      .clka(clock),
      .rdb(cacheData),   //the data to memory
      .wdb(RDreturn),      //the data from memory 
      .ab({aq[9:3], cacheAddr}),     //line address , cnt 
      .web(Dmiss & (RDdest == whichCore)),     //write enable 
      .enb(1'b1),
      .clkb(clock)
    );
  end
  else begin : dcache_sim
    reg [31:0] dataCache[1023:0];
    reg [9:0] dAddrA,dAddrB;
    always @(posedge clock) begin
      dAddrA <= aq[9:0];  // sync read for BRAM	
      dAddrB <= {aq[9:3], cacheAddr};  // sync read for BRAM	
      if (writeDdata) dataCache[aq[9:0]] <= wq;
      if (Dmiss & (RDdest == whichCore)) 
        dataCache[{aq[9:3], cacheAddr}] <= RDreturn;
    end
    assign rqDCache = dataCache[dAddrA];
    assign cacheData = dataCache[dAddrB];

    initial $readmemh(D_INIT,dataCache);
  end
endgenerate
 
  //Interactions with the ring
  assign dcDriveRing = (state != idle);

  //cjt modified to use RingOut[29] on Address slots to indicate 0=D, 1=I
  assign dcRingOut = 
    (~selDCacheIO & (state == waitToken) & (SlotTypeIn == Token)) ?
      ((Dmiss & Ddirty) ? (RingIn + 10) : (RingIn + 1)) :
    (selDCacheIO & (state == waitToken) & (SlotTypeIn == Token)) ? RingIn + 9 :  
    (state == readCache) ? cacheData :
    (state == sendWA) ? {4'b0000, Dtag[20:0], aq[9:3]} :
    (state == sendRA) ? (Dmiss ? {4'b0001, aq[30:3]} : {4'b0011, pcx[30:3]}) :
    RingIn;

  assign dcSlotTypeOut = (state == readCache) ? WriteData :
    ((state == sendRA) | (state == sendWA)) ? Address :
    SlotTypeIn;

  assign dcSrcDestOut = ((state == sendRA) | (state == sendWA)) ? whichCore :
    SrcDestIn;

  always @(posedge clock) select <= selDCache & ~done;

  //A Dmiss doesn't generate done
  assign done = 
    (select & Dhit) | 
    (selDCacheIO & (lineCnt[7]) & 
     ((state == doFlush) | (state == doInvalidate)));

  assign wrq = select & Dhit &  read;

  assign rwq = select & Dhit & ~read;

  assign Dhit = (Dtag[20:0] == aq[30:10]) & (state == idle) & ~Dinvalid;

  assign Ddirty = Dtag[21] & ~Dinvalid;

  assign Ihit = (Itag[20:0] == pcx[30:10]);

  assign incCnt = (state == readCache) | (RDdest == whichCore);

  assign cacheAddr = (state == readCache) ? cnt + 1 : cnt;

  always @(posedge clock) if(reset) cnt <= 0; else if (incCnt) cnt <= cnt + 1;

  assign decLineAddr = 
    ((state == doInvalidate) |
     ((state == doFlush) & ~Ddirty) |  //invalid or clean => stay in doFlush
     (selDCacheIO & (state == sendWA)));

  always @(posedge clock) 
    if(reset) lineCnt <= 0;
    else if((state == idle) & selDCacheIO) lineCnt <= {1'b0, aq[16:10]}; 
    else if(decLineAddr) lineCnt <= lineCnt - 1;

  assign writeDdata = select & ~read & Dhit;

  assign writeDtag =
    //load Dcache from memory
    (Dmiss & (state == readData) & (cnt == 7) & (RDdest == whichCore)) |  
    //write to a line makes it clean
    writeDdata |  
    //flushing a line makes it clean
    (selDCacheIO & (state == readCache) & (cnt == 7)) | 
    //makes the line invalid
    ((state == doInvalidate) & ~lineCnt[7]);  

  assign preWriteItag = 
    ~Dmiss & (state == readData) & (cnt == 7) & (RDdest == whichCore);

  always @(posedge clock) writeItag <= preWriteItag;

  always @(posedge clock) begin
    if(reset) state <= idle;
    else case(state)
      idle:
        if(select & ~Dhit) begin
          flushing <= 1'b0;
          Dmiss <= 1'b1;
          state <= waitToken;  //Dmiss
        end else if(~Ihit) begin
          flushing <= 1'b0;
          Dmiss <= 1'b0;
          state <= waitToken;  //Imiss
        end else if (selDCacheIO & aq[17]) begin
          state <= doInvalidate;
        end else if (selDCacheIO & ~aq[17]) begin
          flushing <= 1'b1;
          state <= doFlush;
        end

      doInvalidate: if(lineCnt[7]) state <= idle;
 
      doFlush:
        if(lineCnt[7]) state <= idle;
        else if(Ddirty) state <= waitToken;	 //find a dirty line to flush

      waitToken: 
        if ((SlotTypeIn == Token) & ~msgrWaiting & 
            ~lockerWaiting & ~barrierWaiting) begin
          if(RingIn[7:0] == 0) begin
            if(flushing) state <= readCache;
            else state <= sendRA; //send the read address first
          end else begin
            burstLength <= RingIn[7:0];
            state <= waitN;
          end
        end

      sendRA: 
        if (Dmiss & Ddirty) state <= readCache; 
        else state <= waitRD;

      waitN: begin  //wait for the end of the train
        burstLength <= burstLength - 1;
        if(burstLength == 1) begin
          if(flushing) state <= readCache;
          else state <= sendRA;
        end
      end

      readCache: if(cnt == 7) state <= sendWA;

      sendWA: 
        if(~flushing) state <= waitRD;
        else state <= doFlush;

      waitRD: if(RDdest == whichCore) state <= readData;

      readData: if((cnt == 7) & (RDdest == whichCore)) state <= preIdle;

      preIdle: state <= idle;
    endcase
  end
endmodule
