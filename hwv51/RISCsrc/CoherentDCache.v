/*
  Coherent DCache
  
  -- Cache Line states
    INVALID  - the line is unused
    SHARED   - the data in line is correct but only reads allowed
    MODIFIED - only this core has this address in cache    
    FYI, cache line state in code is sometimes referenced as cache line status.
  
  -- Ring Data of Addres SlotType
  There are two different types of Address Slots, one for reads one for writes
  29th bit decides that. 
  
    -- Read Address SlotType
    [1 bit - if set this is resent Address slot from memory controller]
    [1 bit - if set core already has data just needs exlusive access]
    [1 bit - if set this is exlusive read request]
    1'b1 - 29th bit is always 1 for read address slot type
    [28 bits of Address]
    
    -- Write/Flush Address SlotType
    [2 bits - unused]
    [1 bit = if set this is requested flush because some other core wants data]
    1'b0 - 29th bit is always 0 for write address slot type
    [28 bits of Address]
  
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
  output decLineAddr,
  
  input [3:0] whichCore,

  //ring signals
  input [31:0] RingIn,
  input [3:0] SlotTypeIn,
  input [3:0] SourceIn,

  //addition for separate read data return ring.
  //cache never modifies the data or dest, so there are no outputs
  input [31:0] RDreturn,
  input [3:0] RDdest,

  output [31:0] dcRingOut,
  output [3:0] dcSlotTypeOut,
  output [3:0] dcSourceOut,
  output dcDriveRing,
  output dcWantsToken,
  input  dcAcquireToken,  

  //instruction cache signals
  input [9:0] pcMux,
  input [30:0] pcx,
  input stall,
  output [31:0] instx,
  output Ihit  
);
    
  // DCache Line Status values
  localparam INVALID   = 0;
  localparam SHARED    = 1;
  localparam EXCLUSIVE = 2;  // Not Used for now
  localparam MODIFIED  = 3;
  
  // DMC primitives
  localparam DMCCachePush = 4'd0;
  
  // FSM States
  localparam preidle                = 0;
  localparam idle                   = 1;
  localparam readAQ                 = 2;
  localparam sendRAWaitToken        = 3;
  localparam sendCacheDataWaitToken_= 4;
  localparam sendCacheDataWaitToken = 5;
  localparam sendCacheData          = 6;
  localparam sendWA                 = 7;
  localparam setup                  = 8;
  localparam ioInvalidate           = 9;
  localparam ioFlush                = 10;
  localparam ioReadMeter            = 11;

  // FSM State
  reg [4:0] state;
  reg [31:0] readRequest;
  reg doFlush;
  reg [31:0] flushRequest;
  reg [9:0] flushAddr;
  reg [2:0] readCnt;
  reg ioFlushing;
  reg [6:0] lineCnt;
  
  // This holds state when we are waiting for ReadData
  //    0 - not waiting for RD
  //    1 - waiting for RD for DCache
  //    2 - waste cycle after DMiss
  //    3 - update tag & status for DCache
  //    4 - waiting for RD for ICache 
  //    5, 6 - waste two cycles after resolving ICache miss this probably 
  //           can be changed so those 2 cycles are not wasted
  reg [2:0] waitReadDataState;
  
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
  
  // DCache Meters. 16 32-bit counters.
  //    0 - # of Read Misses
  //    1 - # of Write Misses
  //    2 - # of Reads
  //    3 - # of Writes
  (* ram_style = "distributed" *)
  reg [31:0] meters[15:0];
  integer i;
  initial for (i = 0; i < 16; i = i + 1) meters[i] = 0;
  // ------------------END OF DECLARATIONS---------------------------
    
  // Logic for DCache
  localparam handleNone      = 0;
  localparam handleRequestQ  = 2;
  localparam handleAQ        = 3;
  localparam handleIMiss     = 4;
  localparam resolveDMiss    = 5;
  localparam handleIO        = 6;
  
  wire [2:0] select = 
    (state != idle)                             ? handleNone      :
    (~requestQempty)                            ? handleRequestQ  :
    (selDCache & waitReadDataState == 0)        ? handleAQ        :
    (waitReadDataState == 0 & ~Ihit)            ? handleIMiss     :
    (waitReadDataState == 3)                    ? resolveDMiss    :
    (selDCacheIO)                               ? handleIO        :
                                                  handleNone;
  
  wire AQReadHit = (state == readAQ) & (read) & 
    (requestLineTag == aq[30:10]) & (requestLineStatus != INVALID);
  wire AQWriteHit = (state == readAQ) & (~read) & 
    (requestLineTag == aq[30:10]) & (requestLineStatus == MODIFIED);
  // When we have DCache Write Miss but we already have data in SHARED, we do 
  // not request the data from Memory Controller to speed up the process
  wire doNotRequestRD = 
    (~read) & (requestLineTag == aq[30:10]) & (requestLineStatus == SHARED);    

  // IO Module outputs
  assign wrq = 
    AQReadHit | (read & (select == resolveDMiss)) | (state == ioReadMeter);
  assign rqDCache = 
    (state == ioReadMeter) ? meters[aq[6:3]] : dcacheReadData;
  assign rwq = 
    AQWriteHit | (~read & (select == resolveDMiss));
  assign done = 
    (AQReadHit | AQWriteHit) | (select == resolveDMiss) | 
    ((state == ioInvalidate) & (lineCnt == 0)) | 
    ((state == ioFlush)      & (lineCnt == 0)) |
    (state == ioReadMeter);
    
  assign decLineAddr = 
    (lineCnt > 0) & (state == ioInvalidate | state == ioFlush);

  // Logic for instruction cache
  assign Ihit = (Itag[20:0] == pcx[30:10]);
  assign Iaddr = Ihit ? pcMux[9:0] : pcx[9:0];
  wire preWriteItag = 
    (waitReadDataState == 4) & (readCnt == 7) & (RDdest == whichCore);
  always @(posedge clock) writeItag <= preWriteItag;

  // Logic for DCache meters
  always @(posedge clock) if (!reset) begin
    if (state == readAQ) begin
      // Read/Write Miss
      if (read & ~AQReadHit) meters[0] <= meters[0] + 1;
      else if (~read & ~AQWriteHit) meters[1] <= meters[1] + 1;
      
      // Read/Write Total count
      if (read) meters[2] <= meters[2] + 1;
      else meters[3] <= meters[3] + 1;
    end
    
    // ICache meters
    if (select == handleIMiss) meters[4] <= meters[4] + 1;
    if (Ihit & ~stall) meters[5] <= meters[5] + 1;
  end

  // Ring Interactions
  assign dcWantsToken = 
    (state == sendRAWaitToken) | (state == sendCacheDataWaitToken);
    
  wire resendMessage = 
    (SourceIn == whichCore & SlotTypeIn == `Address & RingIn[31]);
  assign dcDriveRing = 
    // Ring Modifications
    (resendMessage)                                    |
    // Ring Additions
    (state == sendRAWaitToken & dcAcquireToken)        | 
    (state == sendCacheDataWaitToken & dcAcquireToken) | 
    (state == sendCacheData)                           | 
    (state == sendWA);    

  assign dcSourceOut = whichCore;
  assign dcSlotTypeOut = 
    // Ring Modifications
    resendMessage                                              ? SlotTypeIn  :
    // Ring Additions
    (state == sendRAWaitToken | state == sendWA)               ? `Address    : 
    (state == sendCacheDataWaitToken | state == sendCacheData) ? `WriteData  : 
                                                                  4'b0;
  assign dcRingOut = 
    // Ring Modifications
    resendMessage                     ? RingIn                  :
    // Ring Additions
    (state == sendRAWaitToken)        ? readRequest             :
    (state == sendCacheDataWaitToken | 
     state == sendCacheData)          ? dcacheReadData          :
    (state == sendWA)                 ? flushRequest            : 
                                        32'b0; 
    
  always @(posedge clock) begin
    if (reset) begin
      state <= setup;
      lineCnt <= 0;
      readRequest  <= 0;
      flushRequest <= 0;
    end else case (state)
      preidle: state <= idle;
      
      idle: begin
        case (select)
          handleRequestQ:
            if ((requestLineStatus == MODIFIED) & 
                (requestLineTag == requestQout[27:7])) begin
              // if some other core requested the line that we have in MODIFIED
              // state we need to flush it            
              state <= sendCacheDataWaitToken_;
              ioFlushing <= 0;
              flushAddr <= {requestQout[6:0], 3'b000};
              // requested flush, hence 29th bit is set
              flushRequest <= {4'b0010, requestQout[27:0]};
            end
          
          handleAQ: 
            if (~done) state <= readAQ;
            
          handleIMiss: begin
            state <= sendRAWaitToken;
            readRequest <= {4'b0101, pcx[30:3]};
            doFlush <= 0;
          end
          
          // resolveDMiss: Nothing to do here
          
          handleIO: begin
            // Handle DCache IO requests
            if (aq[30:27] == 4'h0) begin
              // flush/invalidate
              state <= (aq[17] ? ioInvalidate : ioFlush);
              lineCnt <= aq[16:10];
            end else if (aq[30:27] == 7) begin
              // Return DCache meter value
              state <= ioReadMeter;              
            end
          end
        endcase
      end
      
      readAQ: 
        if (~AQReadHit & ~AQWriteHit) begin
          state <= sendRAWaitToken;
          readRequest <= {1'b0, doNotRequestRD, ~read, 1'b1, aq[30:3]}; 
          
          ioFlushing <= 0;
          doFlush <= (requestLineStatus == MODIFIED);
          flushAddr <= {aq[9:3], 3'b000};
          flushRequest <= {4'b0000, requestLineTag, aq[9:3]};
        end else begin
          state <= idle;
        end
        
      sendRAWaitToken: begin
        if (dcAcquireToken) begin
          if (doFlush) state <= sendCacheData;
          else state <= idle;
        end
      end
      
      sendCacheDataWaitToken_: begin 
        // need to waste one cycle to correctly set address for DCache
        state <= sendCacheDataWaitToken;
      end
      
      sendCacheDataWaitToken: begin
        if (dcAcquireToken) begin
          state <= sendCacheData;
          flushAddr <= flushAddr + 1;
        end
      end
      
      sendCacheData: begin
        flushAddr <= flushAddr + 1;
        if (flushAddr[2:0] == 3'h7) state <= sendWA;
      end
      
      sendWA: begin
        if (!ioFlushing) state <= idle;
        else state <= ioFlush;
      end
      
      setup: begin
        // setup initial dcache state. For Master Core (1) all cache
        // lines are in MODIFIED state initially.
        if (whichCore != 1) state <= idle;
        else begin
          if (lineCnt == 7'h7F) state <= idle;
          lineCnt <= lineCnt + 1;
        end
      end
      
      ioInvalidate: begin
        if (lineCnt == 0) state <= idle;
        lineCnt <= lineCnt - 1;
      end
      
      ioFlush: begin
        if (requestLineStatus == MODIFIED) begin
          state <= sendCacheDataWaitToken_;
          ioFlushing <= ~(lineCnt == 0);
          flushAddr <= {aq[9:3], 3'b000};
          flushRequest <= {4'b0000, requestLineTag, aq[9:3]};
        end else if (lineCnt == 0) begin
          state <= idle;
        end
        lineCnt <= lineCnt - 1;          
      end
      
      ioReadMeter: state <= idle;
    endcase
  end
  
  always @(posedge clock) begin
    // Wait for RDReturn data and when receive it update the DCache or ICache
    // or if we receive GrantExclusive we do not need to wait for RD anymore.    
    if (reset) begin
      waitReadDataState <= 0;
      readCnt <= 0;
    end
    else begin
      if (state == readAQ & ~AQReadHit & ~AQWriteHit) begin
        waitReadDataState <= 1;
      end else if (select == handleIMiss) begin
        waitReadDataState <= 4;
      end else if (waitReadDataState == 1 & SourceIn == whichCore &
                   SlotTypeIn == `GrantExclusive) begin
        waitReadDataState <= 3;
      end else if ((waitReadDataState == 1) | (waitReadDataState == 4)) begin
        if (RDdest == whichCore) begin
          if (readCnt == 7) waitReadDataState <= waitReadDataState + 1;
          readCnt <= readCnt + 1;
        end
      end else if ((waitReadDataState == 2) | (waitReadDataState == 5)) begin
        waitReadDataState <= waitReadDataState + 1;
      end else if ((waitReadDataState == 3 & select == resolveDMiss) | 
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
  
  // Cache Line that we want Status and Tag for
  wire [6:0] requestLine = 
    (state == idle & ~requestQempty)   ? requestQout[6:0] :
    (state == setup)                   ? lineCnt[6:0]     :
                                         aq[9:3];
                                                       
  wire wrDCacheTag = (state == readAQ & (~AQReadHit & ~AQWriteHit));
  dcacheTag DataCacheTag (
    .a(requestLine),    // Bus [6 : 0] 
    .d(aq[30:10]),      // Bus [20 : 0] 
    .dpra(RingIn[6:0]), // Bus [6 : 0] 
    .clk(clock),
    .we(wrDCacheTag),
    .spo(requestLineTag), // Bus [20 : 0] 
    .dpo(ringLineTag)     // Bus [20 : 0] 
  ); 

  wire wrDCacheStatus = 
    (state == setup & whichCore == 4'b1)                    |
    (select == handleRequestQ)                              |
    (select == resolveDMiss & ~read)                        |
    (state == readAQ & (~AQReadHit & ~AQWriteHit))          | 
    (state == ioInvalidate & requestLineStatus != MODIFIED) |
    (state == ioFlush & requestLineStatus == MODIFIED);
  wire [1:0] newStatus = 
    (state == setup)                  ? MODIFIED :
    (select == handleRequestQ)        ? (~requestQout[29] ? SHARED : INVALID) :
    (select == resolveDMiss & ~read)  ? MODIFIED : 
    (state == readAQ)                 ? (read ? SHARED : INVALID) : 
    (state == ioInvalidate)           ? INVALID  : 
    (state == ioFlush)                ? SHARED   : INVALID;
  dcacheStatus DataCacheStatus (
    .a(requestLine), // Bus [6 : 0] 
    .d(newStatus), // Bus [1 : 0] 
    .dpra(RingIn[6:0]), // Bus [6 : 0] 
    .clk(clock),
    .we(wrDCacheStatus),
    .spo(requestLineStatus), // Bus [1 : 0] 
    .dpo(ringLineStatus)     // Bus [1 : 0] 
  ); 
  
  wire rdRequestQ = (select == handleRequestQ);
  // Check incoming AddressRequest-s on the ring and if someone is 
  // requesting a read or exclusive read on an Address that we have in our 
  // cache schedule in Request Queue to deal with it.
  wire wrRequestQ = 
    // Handle stuff that comes on the ring from other cores
    // Address Request from some other core, the tag is valid and matches
    ((SlotTypeIn == `Address) & (SourceIn > 0) & (SourceIn <= `nCores) & 
     (SourceIn != whichCore) & (ringLineTag == RingIn[27:7])) &
    (((RingIn[29:28] == 2'b01) & (ringLineStatus == MODIFIED)) | 
     ((RingIn[29:28] == 2'b11) & (ringLineStatus != INVALID)));
  dcacheRequestQ DataCacheRequestQueue (
    .clk(clock),
    .rst(reset),
    .din(RingIn), // Bus [31 : 0] 
    .wr_en(wrRequestQ),
    .rd_en(rdRequestQ),
    .dout(requestQout), // Bus [31 : 0] 
    .full(),
    .empty(requestQempty),
    .almost_empty()
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

    integer k;
    initial begin
      for (k = 0; k < 1024; k = k + 1) instCache[k] = 32'hDEADBEEF;
      $readmemh(I_INIT,instCache);
    end
  end
endgenerate


  wire wrDCache = AQWriteHit | (~read & (select == resolveDMiss));
  wire [9:0] dcacheAddr =
    // on next cycle i am starting flush
    ((state == sendRAWaitToken & doFlush) |
     (state == sendCacheDataWaitToken_) |
     (state == sendCacheDataWaitToken & ~dcAcquireToken)) ? flushAddr :
    // when flushing
    ((state == sendCacheData & flushAddr[2:0] != 3'h7) |                         
     (state == sendCacheDataWaitToken & dcAcquireToken))  ? flushAddr + 1 :
                                                            aq[9:0];
  wire [31:0] dcacheWriteData = wq;
generate
  if (D_INIT == "NONE") begin : dcache_synth
    dpbram32 dataCache (
      .rda(dcacheReadData), // read data from DCache goes either to 
                            // rqDCache or on Ring during flush
      .wda(dcacheWriteData), // stuff from wq is written in DCache 
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
      if (wrDCache) dataCache[dcacheAddr] <= dcacheWriteData;
      if ((waitReadDataState == 1) && (RDdest == whichCore)) 
        dataCache[{aq[9:3], readCnt}] <= RDreturn;
    end
    assign dcacheReadData = dataCache[dAddrA];

    integer k;
    initial begin
      for (k = 0; k < 1024; k = k + 1) dataCache[k] = 32'hDEADBEEF;
      $readmemh(D_INIT,dataCache);
    end
  end
endgenerate
    
endmodule
