`timescale 1ns / 1ps
/*
  Coherent DCache
  TODO: write more description here
  
  Created By: Zviad Metreveli
*/

module CoherentDCache #(parameter I_INIT="NONE",D_INIT="NONE") (
  //signals common to all local I/O devices:
  input clock, 
  input reset,
  input [30:0] aq,   //the CPU address queue output.  Bit 31 not used
  input read,        //request in AQ is a read
  input [31:0] wq,   //the CPU write queue output
  output rwq,        //read the write queue
  output [31:0] rqDCache, //the CPU read queue input
  output wrq,        //write the read queue
  output done,       //operation is finished. 
                     //Read the AQ, read WQ if operation was write
  input selDCache,
  input selDCacheIO, //invalidate or flush operation
  input [3:0] whichCore,
  input [3:0] EtherCore,

  //ring signals
  input [31:0] RingIn,
  input [3:0] SlotTypeIn,
  input [3:0] SrcDestIn,

  //addition for separate read data return ring.
  //cache never modifies the data or dest, so there are no outputs
  input [31:0] RDreturn,
  input [3:0] RDdest,

  output [31:0] dcRingOut,
  output [3:0] dcSlotTypeOut,
  output [3:0] dcSrcDestOut,
  output dcDriveRing,
  output dcWantsToken,
  input  dcAcquireToken,  

  //instruction cache signals
  input [9:0] pcMux,
  input [30:0] pcx,
  input stall,
  output [31:0] instx,
  output Ihit,
  output decLineAddr,
);
  
  //Slot Types
  parameter Null           = 7;
  parameter Token          = 1;
  parameter Address        = 2;
  parameter WriteData      = 3;
  parameter AddressRequest = 5;  
  parameter GrantExclusive = 6;   
  
  // DCache Line Status values
  localparam INVALID   = 0;
  localparam SHARED    = 1;
  localparam EXCLUSIVE = 2;  // Not Used for now
  localparam MODIFIED  = 3;
  
  // FSM States
  localparam idle = 0;
  localparam sendRAWaitToken = 1;
  localparam sendCacheDataWaitToken = 2;
  localparam sendCacheData = 3;
  localparam sendWA = 4;
  localparam setup = 5;
          
  // FSM State
  reg [3:0] state;
  reg [31:0] readRequest;
  reg doFlush;
  reg [31:0] flushRequest;
  reg [9:0] flushAddr;
  reg [2:0] readCnt;
  reg ioFlushing;
  reg [6:0] lineCnt;

  // This holds state when we are waiting for ReadData
  // 0 - not waiting for RD
  // 1 - waiting for RD for DCache
  // 2 - waste cycle after DMiss
  // 3 - update tag & status for DCache
  // 4 - waiting for RD for ICache 
  // 5, 6 - waste two cycles after resolving ICache miss
  // this probably can be changed so those 2 cycles are not wasted
  reg [2:0] waitForReadDataState;
  
  // Wires from request queue
  wire requestQempty;
  wire [31:0] requestQout;

  // Wires from DCache Tag
  wire [20:0] requestLineTag, ringLineTag;
  
  // Wires from DCache Status
  wire [1:0] requestLineStatus, ringLineStatus;
  
  // Wires from DCache
  wire [31:0] dcacheReadData;
  
  // Wires for ICache
  wire [9:0] Iaddr;
  reg writeItag;
  wire [20:0] Itag;
  // ------------------END OF DECLARATIONS---------------------------

  // Since our DCache BRAM is registered selDCache needs to be asserted at
  // least for one extra cycle so that address from AQ does propagate to our
  // DCache BRAM.
  reg delayedSelDCache
  always @(posedge clock) 
    if (reset) delayedSelDCache <= 0;
    else delayedSelDCache <= done ? 0 : selDCache;
    
  // Logic for DCache
  wire handleRequestQ = (state == idle) & (~requestQempty)
  wire handleAQ = (~handleRequestQ) & (state == idle) & 
    (delayedSelDCache) & (waitReadDataState == 0);
  wire handleICacheRequest = (~handleRequestQ) & (~handleAQ) & 
    (state == idle) & (waitReadDataState == 0) & ~Ihit;
  wire resolveDCacheMiss = (~handleRequestQ) & (~handleAQ) & 
    (~handleICacheRequest) & (state == idle) & (waitReadDataState == 3);
  wire handleIO = (~handleRequestQ) & (~handleAQ) & 
    (~handleICacheRequest) & (~resolveDCacheMiss) & (state == idle) & 
    (selDCacheIO);
  
  wire AQReadHit = (handleAQ) & (read) & 
    (requestLineTag == aq[30:10]) & (requestLineStatus != INVALID)
  wire AQWriteHit = (handleAQ) & (~read) & 
    (requestLineTag == aq[30:10]) & (requestLineStatus == MODIFIED)
  // When we have DCache Write Miss but we already have data, we do not 
  // request data from Memory Controller to speed up the process
  wire doNotRequestRD = 
    (~read) & (requestLineTag == aq[30:10]) & (requestLineStatus == SHARED);

  // When some other core requested something that we have in MODIFIED state
  wire doRequestedFlush = (handleRequestQ) &
    (requestLineStatus == MODIFIED) & (requestLineTag == requestQout[27:7]);
    
  // Cache Line that we want Status and Tag for
  wire [6:0] requestLine = handleRequestQ   ? requestQout[6:0] :
                           (state == setup) ? lineCnt[6:0]     :
                                              aq[9:3];
  // IO Module outputs
  assign wrq = AQReadHit | (read & resolveDCacheMiss);  
  assign rqDCache = dcacheReadData;
  assign rwq = AQWriteHit | (~read & resolveDCacheMiss);
  assign done = 
    (AQReadHit | AQWriteHit) | (resolveDCacheMiss) | ;

  // Logic for instruction cache
  assign Ihit = (Itag[20:0] == pcx[30:10]);
  assign [9:0] Iaddr = Ihit ? pcMux[9:0] : pcx[9:0];
  assign preWriteItag = 
    (waitReadDataState == 4) & (readCnt == 7) & (RDdest == whichCore);
  always @(posedge clock) writeItag <= preWriteItag;

  // Ring Interactions
  assign dcWantsToken = 
    (state == sendRAWaitToken) | (state == sendCacheDataWaitToken);
  assign dcDriveRing = 
    (state == sendRAWaitToken & dcAcquireToken) | 
    (state == sendCacheDataWaitToken & dcAcquireToken) | 
    (state == sendCacheData) | (state == sendWA);
    
  assign dcSourceOut = whichCore;
  assign dcSlotTypeOut = 
    (state == sendRAWaitToken | state == sendWA) ? Address : 
    (state == sendCacheDataWaitToken | state == sendCacheData) ? WriteData : 
    4'b0;
  assign dcRingOut = 
    (state == sendRAWaitToken)        ? readRequest    :
    (state == sendCacheDataWaitToken | 
     state == sendCacheData)          ? dcacheReadData :
    (state == sendWA)                 ? flushRequest   : 32'b0;
    
  always @(posedge clock) begin
    if (reset) begin
      state <= setup;
      waitForReadDataState <= 0;
      lineCnt <= 0;
    end else case (state)
      idle: begin
        if (handleRequestQ) begin
          if (doRequestedFlush) begin
            // if some other core requested the line that we have in MODIFIED
            // state we need to flush it            
            state <= sendCacheDataWaitToken;
            ioFlushing <= 0;
            flushAddr <= {requestQout[6:0], 3'b000};
            // requested flush, hence 29th bit is set
            flushRequest <= {4'b0010, requestQout[27:0]};            
          end
        end else if (handleAQ) begin
          if (~AQReadHit & ~AQWriteHit) begin
            state <= sendRA;
            readRequest <= {1'b0, doNotRequestRD, ~read, 1'b1, aq[30:3]}; 
            
            ioFlushing <= 0;
            doFlush <= (requestLineStatus == MODIFIED);
            flushAddr <= {aq[9:3], 3'b000};
            flushRequest <= {4'b0000, requestLineTag, aq[9:3]};
          end
        end else if (handleICacheRequest) begin
          state <= sendRA;
          readRequest <= {4'b0001, pcx[30:3]};
          doFlush <= 0;
        end else if (resolveDCacheMiss) begin
          // Nothing to do here
        end else if (handleIO) begin
          // Nothing to do here yet, just assert done
          /*
            // Handle DCache IO requests
            set_lineCnt = {aq[16:10]};
            if (aq[17]) next_state = dcacheio_invalidate;
            else next_state = dcacheio_flush;
          */
        end
      end
      
      sendRAWaitToken: begin
        if (dcAcquireToken) begin
          if (doFlush) state <= sendCacheData;
          else state <= idle;
        end
      end
      
      sendCacheDataWaitToken: begin
        if (dcAcquireToken) begin
          flushAddr <= flushAddr + 1;
          state <= sendCacheData;
        end
      end
      
      sendCacheData: begin
        flushAddr <= flushAddr + 1;
        if (flushAddr[2:0] == 7) next_state = sendWA;
      end
      
      sendWA: begin
        if (!ioFlushing) state <= idle;
        //else state <= dcacheio_flush;
      end
      
      setup: begin
        // setup initial dcache state. For Master Core (1) all cache
        // lines are in MODIFIED state initially.
        if (whichCore != 4'b1) state <= idle;
        else begin
          if (lineCnt == 7'h7F) state <= idle;
          lineCnt <= lineCnt + 1;
        end
      end      
    endcase
  end
  
  always @(posedge clock)
    // Wait for RDReturn data and when receive it update the DCache or ICache
    // or if we receive GrantExclusive we do not need to wait for RD anymore.    
    if (reset) begin
      waitReadDataState <= 0;
      readCnt <= 0;
    end
    else begin
      if (waitReadDataState == 1 & SlotTypeIn == GrantExclusive & 
          SourceIn == whichCore) begin
        waitReadDataState <= 3;
      end else if ((waitReadDataState == 1) | (waitReadDataState == 4)) begin
        if (RDdest == whichCore) begin
          if (readCnt == 7) waitReadDataState <= waitReadDataState + 1;
          readCnt <= readCnt + 1;
        end
      end else if ((waitReadDataState == 2) | (waitReadDataState == 5)) begin
        waitReadDataState <= waitReadDataState + 1;
      end else if ((waitReadDataState == 3 & resolveDCacheMiss) | 
                   (waitReadDataState == 6)) begin
        waitReadDataState <= 0;
      end
    end
  end
  
  itagmemX instTag (
    .a(pcx[9:3]), 
    .d(pcx[30:10]),
    .clk(clock),
    .we(writeItag),
    .spo(Itag)
  ); 
  
  wire wrDCacheTag = handleAQ & (~AQReadHit & ~AQWriteHit);  
  dcacheTag DataCacheTag (
    .a(requestLine), // Bus [6 : 0] 
    .d(aq[30:10]), // Bus [20 : 0] 
    .dpra(RingIn[6:0]), // Bus [6 : 0] 
    .clk(clock),
    .we(wrDCacheTag),
    .spo(requestLineTag), // Bus [20 : 0] 
    .dpo(ringLineTag)     // Bus [20 : 0] 
  ); 

  wire [1:0] wrDCacheStatus = 
    (state == setup & whichCore == 4'b1) | (handleRequestQ) | 
    (handleAQ & (~AQReadHit & ~AQWriteHit)) | (resolveDCacheMiss & ~read);
  wire newStatus = 
    (state == setup)            ? MODIFIED :
    (handleRequestQ)            ? (~requestQout[29] ? SHARED : INVALID) :
    (resolveDCacheMiss & ~read) ? MODIFIED : 
    (handleAQ & read)           ? SHARED   : INVALID;
  dcacheStatus DataCacheStatus (
    .a(requestLine), // Bus [6 : 0] 
    .d(newStatus), // Bus [1 : 0] 
    .dpra(RingIn[6:0]), // Bus [6 : 0] 
    .clk(clock),
    .we(wrDCacheStatus),
    .spo(requestLineStatus), // Bus [1 : 0] 
    .dpo(ringLineStatus)     // Bus [1 : 0] 
  ); 
  
  wire rdRequestQ = handleRequestQ;
  // Check incoming AddressRequest-s on the ring and if someone is 
  // requesting a read or exclusive read on an Address that we have in our 
  // cache schedule in Request Queue to deal with it.
  wire wrRequestQ = 
    // Handle stuff that comes on the ring from other cores
    // Address Request from some other core, the tag is valid and matches
    ((SlotTypeIn == Address | SlotTypeIn == AddressRequest) & 
     (SourceIn > 0) & (SrcDestIn < SourceIn) & 
     (ringLineTag == RingIn[27:7]) & (ringLineStatus != INVALID)) &
    ((RingIn[29:28] == 2'b01 & (ringLineStatus == MODIFIED)) | 
     (RingIn[29:28] == 2'b11));
  dcacheRequestQ DataCacheRequestQueue (
    .clk(clock),
    .rst(reset),
    .din(RingIn), // Bus [31 : 0] 
    .wr_en(wrRequestQ),
    .rd_en(rdRequestQ),
    .dout(requestQout), // Bus [31 : 0] 
    .full(),
    .empty(requestQempty),
    .almost_empty(requestQalmostEmpty)
  );    

generate
  if (I_INIT == "NONE") begin : icache_synth
    dpbram32 instCache (
      .rda(instx), //the instruction
      .wda(32'b0),
      .aa(Iaddr),  
      .wea(1'b0), //write enable 
      .ena(~stall | ~Ihit),
      .clka(clock),
      .rdb(),
      .wdb(RDreturn), //the data from memory 
      .ab({pcx[9:3], readCnt}), //line address , cnt 
      .web((waitReadDataState == 4) && (RDdest == whichCore)), //write enable 
      .enb(1'b1),
      .clkb(clock)
    );
  end
  else begin : icache_sim
    reg [31:0] instCache[1023:0];
    reg [9:0] instAddr;
    always @(posedge clock) begin
      if (~stall | ~Ihit) instAddr <= Iaddr;  // sync read for BRAM	
      if ((waitReadDataState == 4) && (RDdest == whichCore))
        instCache[{pcx[9:3], readCnt}] <= RDreturn;
    end
    assign instx = instCache[instAddr];

    initial $readmemh(I_INIT,instCache);
  end
endgenerate


  wire wrDCache = AQWriteHit | (~read & resolveDCacheMiss);
  wire [9:0] dcacheAddr =
    ((state == sendRAWaitToken & doFlush) | (doRequestedFlush) | 
     (state == sendCacheDataWaitToken) | (state == sendCacheData)) ? 
    flushAddr : aq[9:0];
generate
  if (D_INIT == "NONE") begin : dcache_synth
    dpbram32 dataCache (
      .rda(dcacheReadData), // read data from DCache goes either to 
                            // rqDCache or on Ring during flush
      .wda(wq),         // stuff in wq is written in DCache 
                        // when there is a hit on a write
      .aa(dcacheAddr),
      .wea(wrDCache),
      .ena(1'b1),
      .clka(clock),
      .rdb(),               // second read port is unused
      .wdb(RDreturn),       // the data from memory 
      .ab({aq[9:3], readCnt}), // line address, cnt 
      .web((waitReadDataState == 1) && (RDdest == whichCore)),
      .enb(1'b1),
      .clkb(clock)
    );
  end
  else begin : dcache_sim
    reg [31:0] dataCache[1023:0];
    reg [9:0] dAddrA,dAddrB;
    always @(posedge clock) begin
      dAddrA <= dcacheAddr;  // sync read for BRAM	
      if (wrDCache) dataCache[dcacheAddr] <= wq;
      if ((waitReadDataState == 1) && (RDdest == whichCore)) 
        dataCache[{aq[9:3], readCnt}] <= RDreturn;
    end
    assign dcacheReadData = dataCache[dAddrA];

    initial $readmemh(D_INIT,dataCache);
  end
endgenerate
    
endmodule
