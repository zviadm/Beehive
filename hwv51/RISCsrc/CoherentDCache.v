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
  output reg rwq,    //read the write queue
  output [31:0] rqDCache, //the CPU read queue input
  output reg wrq,    //write the read queue
  output reg done,   //operation is finished. 
                     //Read the AQ, read WQ if operation was write
  input selDCache,
  input selDCacheIO, //invalidate or flush operation
  input [3:0] whichCore,
  input [3:0] EtherCore,

  //ring signals
  input  [31:0] RingIn,
  input  [3:0] SlotTypeIn,
  input  [3:0] SrcDestIn,

  //addition for separate read data return ring.
  //cache never modifies the data or dest, so there are no outputs
  input [31:0] RDreturn,
  input [3:0] RDdest,

  output reg [31:0] dcRingOut,
  output reg [3:0] dcSlotTypeOut,
  output reg [3:0] dcSrcDestOut,
  output reg dcDriveRing,

  //instruction cache signals
  input [9:0] pcMux,
  input [30:0] pcx,
  input stall,
  output [31:0] instx,
  output reg Ihit,
  output reg decLineAddr,
  input msgrWaiting,
  input lockerWaiting,
  input barrierWaiting
);
  
  //Slot Types
  parameter Null = 4'd7;
  parameter Token = 4'd1;
  parameter Address = 4'd2;
  parameter WriteData = 4'd3;
  parameter AddressRequest = 4'd5;  
  parameter GrantExclusive = 4'd6;   
  
  // DCache Line Status values
  localparam INVALID  = 0;
  localparam SHARED   = 1;
  localparam EXCLUSIVE = 2;  // Not Used for now
  localparam MODIFIED  = 3;
  
  // FSM States
  localparam idle = 0;
  localparam wait_token = 1;
  localparam waitN = 2;
  localparam sendRA = 3;
  localparam read_cache = 4;
  localparam sendWA = 5;
  localparam setup = 6;
  localparam dcacheio_invalidate = 7;
  localparam dcacheio_flush = 8;
  
  // Select Possibilites
  localparam handle_dcache_request = 1;
  localparam update_dcache = 2;
  localparam handle_icache_request = 3;
  localparam handle_requestQ = 4;
  localparam handle_dcacheio_request = 5;
    
  // Wires for request queue
  reg wrRequestQ;
  reg [31:0] requestQin;
  reg rdRequestQ;
  wire requestQempty;
  wire requestQalmostEmpty;
  wire [31:0] requestQout;
    
  // FSM State and Next State
  reg [3:0] state, next_state;
  reg [2:0] select, set_select;
  reg [7:0] burstLength, set_burstLength;
  reg doReadRequest, set_doReadRequest;
  reg doNotRequestRD, set_doNotRequestRD;
  reg doFlushAfterRead, set_doFlushAfterRead;
  reg [31:0] flushRequest, set_flushRequest;
  reg [9:0] flushAddr, set_flushAddr;
  reg [2:0] readCnt, set_readCnt;
  reg [6:0] lineCnt, set_lineCnt;
  reg ioFlushing, set_ioFlushing;

  // This holds state when we are waiting for ReadData
  // 0 - not waiting for RD
  // 1 - waiting for RD for DCache
  // 2 - waste cycle after DMiss
  // 3 - update tag & status for DCache
  // 4 - waiting for RD for ICache 
  // 5, 6 - waste two cycles after resolving ICache miss
  // this probably can be changed so those 2 cycles are not wasted
  reg [2:0] waitingForReadData, set_waitingForReadData;
    
  // Cache Line that we want Status and Tag for
  wire [6:0] requestLine;
  
  // Wires for DCache Tag
  reg wrDCacheTag;
  wire [20:0] requestLineTag, ringLineTag;
  
  // Wires for DCache Status
  reg wrDCacheStatus;
  reg [1:0] newStatus;
  wire [1:0] requestLineStatus, ringLineStatus;
  
  // Wires for DCache
  reg wrDCache;
  wire [9:0] dcacheAddr;
  wire [31:0] dcacheReadData;
  
  // Wire for ICache
  reg [9:0] Iaddr;
  reg writeItag, set_writeItag;
  wire [20:0] Itag;
  // ------------------END OF DECLARATIONS---------------------------
    
  assign rqDCache = dcacheReadData;
  // DCache Address logic
  assign dcacheAddr = (next_state == idle) ? aq[9:0] : set_flushAddr;
  // Request Line Logic
  assign requestLine = 
    (state == idle && select == handle_requestQ) ? requestQout[6:0] :
                                (state == setup) ? lineCnt[6:0]     :
                                                   aq[9:3];
  always @(posedge clock) begin
    if (reset) begin
      state <= setup;
      select <= idle;      
      burstLength <= 0;
      
      waitingForReadData <= 0;
      readCnt <= 0;
      lineCnt <= 0;
      
      doReadRequest <= 0;
      doNotRequestRD <= 0;
      doFlushAfterRead <= 0;      
      flushRequest <= 0;
      flushAddr <= 0;
      ioFlushing <= 0;
      
      writeItag <= 0;
    end 
    else begin
      state <= next_state;
      select <= set_select;
      burstLength <= set_burstLength;

      waitingForReadData <= set_waitingForReadData;    
      readCnt <= set_readCnt;
      lineCnt <= set_lineCnt;
      
      doReadRequest <= set_doReadRequest;
      doNotRequestRD <= set_doNotRequestRD;
      doFlushAfterRead <= set_doFlushAfterRead;      
      flushRequest <= set_flushRequest;
      flushAddr <= set_flushAddr;
      ioFlushing <= set_ioFlushing;
      
      writeItag <= set_writeItag;
    end
  end
  
  always @(*) begin   
    // Default values
    next_state = state;
    set_burstLength = burstLength;
    set_waitingForReadData = waitingForReadData;    

    set_lineCnt = lineCnt;
    set_readCnt = readCnt;
    
    set_doReadRequest = doReadRequest;
    set_doNotRequestRD = doNotRequestRD;
    set_doFlushAfterRead = doFlushAfterRead;    
    set_flushRequest = flushRequest;
    set_flushAddr = flushAddr;
    set_ioFlushing = ioFlushing;
    
    wrDCache = 0;
    wrDCacheTag = 0;
    wrDCacheStatus = 0;
    newStatus = 0;

    rdRequestQ = 0;
    wrRequestQ = 0;
    requestQin = 0;            
    
    dcRingOut = RingIn;
    dcSlotTypeOut = SlotTypeIn;
    dcSrcDestOut = SrcDestIn;
    dcDriveRing = (state == wait_token || state == sendRA || 
                   state == read_cache || state == sendWA);

    wrq = 0;
    rwq = 0;
    done = 0;
    decLineAddr = 0;
    
    // Logic for instruction cache
    Ihit = (Itag[20:0] == pcx[30:10]);
    Iaddr = Ihit ? pcMux[9:0] : pcx[9:0];
    set_writeItag = (waitingForReadData == 4) && (readCnt == 7) && 
                    (RDdest == whichCore);    
        
    // Check incoming AddressRequest-s on the ring and if someone is 
    // requesting a read or exclusive read on an Address that we have in our 
    // cache schedule in Request Queue to deal with it.
    if ((SlotTypeIn == Address || SlotTypeIn == AddressRequest) &&
       (SrcDestIn > 0) && (SrcDestIn < EtherCore) &&
       (ringLineTag == RingIn[27:7]) && (ringLineStatus != INVALID)) begin
      // Handle stuff that comes on the ring from other cores
      // Address Request from some other core, the tag is valid and matches
      if ((RingIn[29:28] == 2'b01 && (ringLineStatus == MODIFIED)) || 
         (RingIn[29:28] == 2'b11)) begin
        // it is a read request and wehave it in MODIFIED state or it is 
        // an exclusive read request, we need to add it to our queue of 
        // things to process
        wrRequestQ = 1;
        requestQin = RingIn;
      end      
    end
        
    case (state)
      idle: begin
        case (select)
          handle_dcache_request: begin
            // Handle DCache access request from AQ
            if ((requestLineTag == aq[30:10]) &&
                ((read && requestLineStatus != INVALID) || 
                 (~read && requestLineStatus == MODIFIED))) begin
              // We have a data cache hit
              if (read) wrq = 1;
              else begin
                rwq = 1;
                wrDCache = 1;
              end
              done = 1;              
            end
            else begin
              // We have a data cache miss
              next_state = wait_token;
              set_waitingForReadData = 1;
              
              set_doReadRequest = 1;
              set_doNotRequestRD = (~read) && (requestLineTag == aq[30:10]) && 
                                   (requestLineStatus == SHARED);
              set_doFlushAfterRead = (requestLineStatus == MODIFIED);
              set_ioFlushing = 0;
              set_flushAddr = {aq[9:3], 3'b000};
              set_flushRequest = {4'b0000, requestLineTag, aq[9:3]};
              
              wrDCacheTag = 1;
              wrDCacheStatus = 1;
              if (read) newStatus = SHARED;
              else newStatus = INVALID;
            end            
          end
          
          update_dcache: begin
            // Resolve DCache miss, after we have already received
            // RD from memory and update DCache with it
            set_waitingForReadData = 0;            
            if (read) wrq = 1;
            else begin
              rwq = 1;
              wrDCache = 1;
            end
            done = 1;              
          
            // After receiving RD return need to update STATUS
            // only if we issued an exclusive read.
            if (~read) begin
              wrDCacheStatus = 1;
              newStatus = MODIFIED;
            end
          end
          
          handle_icache_request: begin
            // Handle ICache miss
            next_state = wait_token;          
            set_doReadRequest = 1;
            set_doFlushAfterRead = 0;
            set_waitingForReadData = 4;
          end
          
          handle_requestQ: begin
            // Handle requests from other cores            
            rdRequestQ = 1;
            
            if ((requestLineStatus != INVALID) && 
                (requestLineTag == requestQout[27:7])) begin
              // If requested address line still contains correct tag and is 
              // not invalid
              if (requestLineStatus == MODIFIED) begin
                // if the line is in modified state we need to flush it
                next_state = wait_token;
                set_doReadRequest = 0;
                set_ioFlushing = 0;
                set_flushAddr = {requestQout[6:0], 3'b000};
                // requested flush, hence 29th bit is set
                set_flushRequest = {4'b0010, requestQout[27:0]};
              end
              
              wrDCacheStatus = 1;
              if (~requestQout[29]) newStatus = SHARED;
              else newStatus = INVALID;
            end
          end
          
          handle_dcacheio_request: begin
            // Handle DCache IO requests
            set_lineCnt = {aq[16:10]};
            if (aq[17]) next_state = dcacheio_invalidate;
            else next_state = dcacheio_flush;
          end
        endcase
      end 

      wait_token: begin
        // wait for token on the ring to attach read/flush requests at the end
        if ((SlotTypeIn == Token) & ~msgrWaiting & 
            ~lockerWaiting & ~barrierWaiting) begin
          if(RingIn[7:0] == 0) begin
            if (doReadRequest) next_state = sendRA;
            else next_state = read_cache;
          end
          else begin
            set_burstLength = RingIn[7:0];
            next_state = waitN;
          end
          dcRingOut = 
            RingIn + (doReadRequest ? (doFlushAfterRead ? 10 : 1) : 9);
        end
      end
      
      waitN: begin
        // wait till the end of the token "train"
        if (burstLength == 1) begin
          if (doReadRequest) next_state = sendRA;
          else next_state = read_cache;
        end
        set_burstLength = burstLength - 1;
      end
      
      sendRA: begin
        // send read request on the ring, for DCache or ICache miss
        // depending on value of waitingForReadData
        if (doFlushAfterRead) next_state = read_cache;
        else next_state = idle;      
        dcSlotTypeOut = Address;
        dcSrcDestOut = whichCore;        
        if (waitingForReadData == 1) 
          dcRingOut = {1'b0, doNotRequestRD, ~read, 1'b1, aq[30:3]}; 
        else if (waitingForReadData == 4) 
          dcRingOut = {4'b0001, pcx[30:3]};
      end
      
      read_cache: begin
        // flush contents of DCache on the ring for given cache line 
        // (8 words total)
        if (flushAddr[2:0] == 7) next_state = sendWA;
        set_flushAddr = flushAddr + 1;        
        dcSlotTypeOut = WriteData;
        dcSrcDestOut = whichCore;
        dcRingOut = dcacheReadData;
      end
      
      sendWA: begin
        // send flush request on the ring
        if (!ioFlushing) next_state = idle;
        else next_state = dcacheio_flush;
        dcSlotTypeOut = Address;
        dcSrcDestOut = whichCore;
        dcRingOut = flushRequest;
      end      
      
      setup: begin
        // setup initial dcache state. For Master Core (1) all cache
        // lines are in MODIFIED state initially.
        if (whichCore != 1) next_state = idle;
        else begin
          if (lineCnt == 127) next_state = idle;
          set_lineCnt = lineCnt + 1;
          wrDCacheStatus = 1;
          newStatus = MODIFIED;
        end
      end
      
      dcacheio_invalidate: begin        
        if (lineCnt == 0) begin
          next_state = idle;
          done = 1;
        end
        else begin
          set_lineCnt = lineCnt - 1;
          decLineAddr = 1;
        end
        
        if (requestLineStatus != MODIFIED) begin
          // lines in MODIFIED state can not be invalidated because
          // MODIFIED lines need to be flushed first so they become available
          // in memory directory
          wrDCacheStatus = 1;
          newStatus = INVALID;
        end
      end
      
      dcacheio_flush: begin                
        if (lineCnt == 0) begin
          next_state = idle;
          done = (requestLineStatus != MODIFIED);
        end
        else begin
          set_lineCnt = lineCnt - 1;
          decLineAddr = 1;
        end
        
        if (requestLineStatus == MODIFIED) begin
          wrDCacheStatus = 1;
          newStatus = SHARED;
          
          next_state = wait_token;
          set_doReadRequest = 0;
          set_ioFlushing = 1;
          set_flushAddr = {aq[9:3], 3'b000};
          set_flushRequest = {4'b0000, requestLineTag, aq[9:3]};
        end        
      end
    endcase
        
    // Wait for RDReturn data and when receive it update the DCache or ICache
    // or if we receive GrantExclusive we do not need to wait for RD anymore.
    if (waitingForReadData == 1 && SlotTypeIn == GrantExclusive && 
        SrcDestIn == whichCore) begin
      set_waitingForReadData = 3;
    end 
    else if ((waitingForReadData == 1) || (waitingForReadData == 4)) begin
      if (RDdest == whichCore) begin
        if (readCnt == 7) set_waitingForReadData = waitingForReadData + 1;
        set_readCnt = readCnt + 1;
      end       
    end
    else if (waitingForReadData == 2 || waitingForReadData == 5) begin
      set_waitingForReadData = waitingForReadData + 1;
    end
    else if (waitingForReadData == 6) begin
      set_waitingForReadData = 0;
    end
    else set_readCnt = 0;
    
    // Logic to set select
    if (~requestQempty && (~rdRequestQ || ~requestQalmostEmpty)) 
      set_select = handle_requestQ;
    else if ((set_waitingForReadData == 0) && selDCache && ~done) 
      set_select = handle_dcache_request;
    else if ((set_waitingForReadData == 0) && ~Ihit) 
      set_select = handle_icache_request;
    else if (set_waitingForReadData == 3) 
      set_select = update_dcache;
    else if (selDCacheIO && ~done) 
      set_select = handle_dcacheio_request;
    else 
      set_select = idle;
  end

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
      .web((waitingForReadData == 4) && (RDdest == whichCore)), //write enable 
      .enb(1'b1),
      .clkb(clock)
    );
  end
  else begin : icache_sim
    reg [31:0] instCache[1023:0];
    reg [9:0] instAddr;
    always @(posedge clock) begin
      if (~stall | ~Ihit) instAddr <= Iaddr;  // sync read for BRAM	
      if ((waitingForReadData == 4) && (RDdest == whichCore))
        instCache[{pcx[9:3], readCnt}] <= RDreturn;
    end
    assign instx = instCache[instAddr];

    initial $readmemh(I_INIT,instCache);
  end
endgenerate
  
  itagmemX instTag (
    .a(pcx[9:3]), 
    .d(pcx[30:10]),
    .clk(clock),
    .we(writeItag),
    .spo(Itag)
  ); 
  
  dcacheTag DataCacheTag (
    .a(requestLine), // Bus [6 : 0] 
    .d(aq[30:10]), // Bus [20 : 0] 
    .dpra(RingIn[6:0]), // Bus [6 : 0] 
    .clk(clock),
    .we(wrDCacheTag),
    .spo(requestLineTag), // Bus [20 : 0] 
    .dpo(ringLineTag)     // Bus [20 : 0] 
  ); 

  dcacheStatus DataCacheStatus (
    .a(requestLine), // Bus [6 : 0] 
    .d(newStatus), // Bus [1 : 0] 
    .dpra(RingIn[6:0]), // Bus [6 : 0] 
    .clk(clock),
    .we(wrDCacheStatus),
    .spo(requestLineStatus), // Bus [1 : 0] 
    .dpo(ringLineStatus)     // Bus [1 : 0] 
  ); 

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
      .web((waitingForReadData == 1) && (RDdest == whichCore)),
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
      if ((waitingForReadData == 1) && (RDdest == whichCore)) 
        dataCache[{aq[9:3], readCnt}] <= RDreturn;
    end
    assign dcacheReadData = dataCache[dAddrA];

    initial $readmemh(D_INIT,dataCache);
  end
endgenerate
    
  dcacheRequestQ DataCacheRequestQueue (
    .clk(clock),
    .rst(reset),
    .din(requestQin), // Bus [31 : 0] 
    .wr_en(wrRequestQ),
    .rd_en(rdRequestQ),
    .dout(requestQout), // Bus [31 : 0] 
    .full(),
    .empty(requestQempty),
    .almost_empty(requestQalmostEmpty)
  );    
endmodule
