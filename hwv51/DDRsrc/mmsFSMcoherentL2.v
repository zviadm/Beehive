`timescale 1ns / 1ps
/*
Memory Model FSM.
  This FSM supports coherent DCaches using a directory based cache coherence.
  Directory is instantiated in RAM. Also simulates coherent L2 cache for each 
  core. L2 cache data is also located in RAM.
  
  Created By: Zviad Metreveli
*/

module mmsFSMcoherentL2 (
  input clock,
  input reset,
  
  // mem op queue
  input memOpQempty,
  output rdMemOp,
  input [3:0] memOpDest,
  input [3:0] memOpType,
  input [31:0] memOpData,

  // mem op write data queue
  input writeDataQempty,
  output rdWriteData,
  input[127:0] writeDataIn,
  
  // resend queue
  output wrResend,
  output [39:0] resendOut,
  
  // wires from DDR read data buffer
  input rbEmpty,
  output rdRB,
  input [127:0] readData,
    
  // wires to DDR controller
  input wbFull,
  input afFull,
  output wrAF,
  output [25:0] afAddress,
  output afRead,
  output wrWB,
  output [127:0] writeData,

  // RD outputs  
  output [31:0] RDreturn,  //separate path for read data return
  output [3:0] RDdest,
  
  output [127:0] RDtoDC,
  output wrRDtoDC
);

  parameter DELAY_ON_HIT         = 0;     // Delay on L2 HIT
  parameter DELAY_ON_MISS_CTC    = 1000;  // Delay on L2 Cache To Cache Miss
  parameter DELAY_ON_MISS_MEMORY = 2000;  // Delay on L2 Miss

  // we need 2^26 entries, each 16 bits.
  // TODO: explain this more
  localparam MEM_DIR_PREFIX = {3'b011};

  // memory directory entry states
  localparam MEM_CLEAN    = 2'b00;
  localparam MEM_WAITING  = 2'b01;
  localparam MEM_MODIFIED = 2'b10;
  
  // L2 cache entries. The entries are overlapping some of the
  // memory directory entries, however this is ok since
  // this are directory entries for directory entry addresses
  // thus they are not used.
  // Each core has it's own L2 cache, entry of address X of core C
  // is located at {L2_ENTRY_PREFIX, X[LOG_CACHE_LINES-1:0], C}
  parameter LOG_CACHE_LINES = 16;
  parameter L2_PREFIX = {MEM_DIR_PREFIX, MEM_DIR_PREFIX};
  
  // FSM state
  reg [5:0] state;
  reg [5:0] nextState;
  reg [5:0] savedNextState;
  reg [12:0] coresToInvalidate;
  reg [3:0] currentCore;
  reg evictL2Entry;
  reg L2CTCMiss;
  
  reg [3:0] opCore;
  reg [31:0] opAddress;
  reg [127:0] opData;
  reg opEvictCore;
  
  // counter for clearing mem directory initially
  reg [23:0] lineCnt;
  
  // wires to/from delayers
  wire rdDelayedRDonHit;
  wire rdDelayedRDonMissMemory;
  wire rdDelayedRDonMissCTC;
  wire [31:0] delayedRDonHit;
  wire [31:0] delayedRDonMissMemory;
  wire [31:0] delayedRDonMissCTC;
  wire [3:0] delayedRDdestOnHit;
  wire [3:0] delayedRDdestOnMissMemory;
  wire [3:0] delayedRDdestOnMissCTC;
  
  // FSM States
  // Memory Directory Operations
  localparam readL2Entry         = 0; 
  localparam readL2Entry_        = 1;
  localparam writeL2Entry        = 2;
  localparam readMemDirEntry     = 3;
  localparam readMemDirEntry_    = 4;
  localparam writeMemDirEntry    = 5;
  localparam clearRB             = 6;
  localparam clearWB             = 7;
  localparam updateMemDirEntry   = 8;
  localparam updateMemDirEntry_1 = 9;
  localparam updateMemDirEntry_2 = 10;
  localparam invalidateL2Entries = 11;
  // Memory Directory Setup
  localparam setupMemDir         = 12;
  localparam setupL2Cache        = 13;
  // Handling Reads
  localparam handleMemOp         = 14;
  localparam checkL2Entry        = 15;
  localparam returnRDonHit       = 16;
  localparam returnRDonHit_1     = 17;
  localparam returnRDonHit_2     = 18;
  localparam handleL2Miss        = 19;
  localparam handleL2Miss_1      = 20;
  localparam handleL2Miss_2      = 21;
  localparam resendOnMiss        = 22;
  localparam returnRDonMiss      = 23;
  localparam returnRDonMiss_1    = 24;
  localparam returnRDonMiss_2    = 25;
  // Handling Writes
  localparam writeDataToMemory   = 26;
  localparam writeDataToMemory_1 = 27;
  localparam skipWrite           = 28;
  localparam skipWrite_1         = 29;
  // Handling CachePush
  localparam handleCachePush     = 30;
  localparam handleCachePush_1   = 31;
  localparam handleCachePush_2   = 32;
  localparam handleCachePush_3   = 33;
  // Final State
  localparam handleMemOpDone     = 35;
  
//---------------------End of Declarations-----------------

  // Read Memory Operation when done
  assign rdMemOp = (state == handleMemOpDone);
  
  // Read write data when handling flush
  assign rdWriteData = (~writeDataQempty) &
    ((state == writeDataToMemory) | (state == writeDataToMemory_1) |
     (state == skipWrite) | (state == skipWrite_1));

  // RDtoDC hack
  assign wrRDtoDC = 
    (state == returnRDonHit_1 | state == returnRDonHit_2) & 
    (memOpDest == 0) & (~rbEmpty);
  assign RDtoDC = readData;
  
  // Resend Queue
  assign wrResend = 
    (state == returnRDonHit & memOpData[30]) | 
    (state == resendOnMiss);
  assign resendOut =
    (state == returnRDonHit & memOpData[30]) ?
      {memOpDest, `GrantExclusive, 4'b0000, memOpData[27:0]} :
    (state == resendOnMiss) ? 
      {memOpDest, memOpType, 2'b10, memOpData[29:0]} : 40'b0;
  
  // Wires for Reading/Writing to DDR RAM
  assign wrAF =
    (state == readL2Entry) | (state == writeL2Entry) | 
    (state == readMemDirEntry) | (state == writeMemDirEntry) | 
    (state == returnRDonHit & ~memOpData[30]) | 
    (state == returnRDonMiss) |
    (state == writeDataToMemory & ~writeDataQempty);
  
  assign afRead = 
    (state == readL2Entry) | (state == readMemDirEntry) |
    (state == returnRDonHit & ~memOpData[30]) |
    (state == returnRDonMiss);
    
  assign afAddress = 
    (state == readL2Entry | state == writeL2Entry)          ? 
      {L2_PREFIX, opAddress[LOG_CACHE_LINES - 1:0], opCore} : 
    (state == readMemDirEntry | state == writeMemDirEntry)  ?
      {MEM_DIR_PREFIX, opAddress[25:3]}                     :
    (state == returnRDonHit & ~memOpData[30])               ? memOpData[25:0] :
    (state == returnRDonMiss)                               ? memOpData[25:0] :
    (state == writeDataToMemory)                            ? memOpData[25:0] :
                                                              26'b0;
                                                              
  assign rdRB = 
    (~rbEmpty) &
    ((state == readL2Entry_)     |
     (state == readMemDirEntry_) |
     (state == clearRB)          |
     (state == returnRDonHit_1)  |
     (state == returnRDonHit_2)  |
     (state == returnRDonMiss_1) |
     (state == returnRDonMiss_2));
    
  assign wrWB =
    (state == writeL2Entry)     | 
    (state == writeMemDirEntry) |
    (state == clearWB)          |
    (state == writeDataToMemory & ~writeDataQempty) |
    (state == writeDataToMemory_1 & ~writeDataQempty);
    
  assign writeData = 
    (state == writeL2Entry | state == writeMemDirEntry)         ? opData      :
    (state == writeDataToMemory | state == writeDataToMemory_1) ? writeDataIn :
    128'b0;
  
  // Wires for modifing Memory Directory Entries
  wire [15:0] memDirEntry = (opData >> ({opAddress[2:0], 4'b0000}));
  wire [15:0] newMemDirEntry =
    (opEvictCore)               ? {memDirEntry & ~(3'b100 << opCore)} :
    (opAddress[29:28] == 2'b00) ? {memDirEntry[15:2], MEM_CLEAN}      :
    (opAddress[29:28] == 2'b10) ? {memDirEntry[15:2], MEM_WAITING}    :
    (opAddress[29:28] == 2'b01) ? 
      {(1 << opCore) | memDirEntry[15:2], MEM_CLEAN}                  :
    (opAddress[29:28] == 2'b11) ? {(1 << opCore), MEM_MODIFIED}       :
                                  16'b0;
  wire [127:0] updateDirEntry = 
    (opData & ~(16'hFFFF << {opAddress[2:0], 4'b0000})) | 
    (newMemDirEntry << {opAddress[2:0], 4'b0000});  
  
  // State Machine outputs and next state calculation
  always @(posedge clock) begin          
    if (reset) begin
      state <= setupMemDir;
      lineCnt <= 0;
    end else case(state)
      // --- L2 Cache and Memory Directory Operations ---
      // Read L2 Cache Entry. Requires: opAddress, opCore
      readL2Entry: state <= readL2Entry_;
      
      readL2Entry_: if (~rbEmpty) begin
        state <= clearRB;
        opData <= readData;
      end
      
      // Write L2 Cache Entry. Requires: opAddress, opCore, opData
      writeL2Entry: state <= clearWB;
      
      // Read Memory Directory Entry. Requires: opAddress
      readMemDirEntry: state <= readMemDirEntry_;
      
      readMemDirEntry_: if (~rbEmpty) begin
        state <= clearRB;
        opData <= readData;
      end
      
      // Write Memory Directory Entry. Requires: opAddress, opData
      writeMemDirEntry: state <= clearWB;
      
      // Clear Read/Write Buffers
      clearRB: if (~rbEmpty) state <= nextState;      
      clearWB: state <= nextState;
      
      // Update Memory Directory entry value
      // Requires: opAddress, opCore, opEvictCore
      updateMemDirEntry: begin
        state <= readMemDirEntry;
        nextState <= updateMemDirEntry_1;
        savedNextState <= nextState;
      end
      
      updateMemDirEntry_1: begin
        state <= updateMemDirEntry_2;
        nextState <= savedNextState;
      end
      
      // Another entrance to updateMemDirEntry, to not reread entry from DDR
      // Requires: opAddress, opCore
      // opData must be equal to 128 bits of read data for line holding memory
      // directory entry
      updateMemDirEntry_2: begin
        state <= writeMemDirEntry;
        opData <= updateDirEntry;

        if (~opEvictCore & opAddress[29:28] == 2'b11 & 
            memDirEntry[15:2] != 0 & memDirEntry[15:2] != (1 << opCore)) begin
          // Invalidate all other L2 entries when setting state to MEM_MODIFIED
          currentCore <= 1;
          coresToInvalidate <= memDirEntry[15:3];
        
          nextState <= invalidateL2Entries;
          savedNextState <= nextState;
        end
      end
      
      invalidateL2Entries: begin      
        if (coresToInvalidate == 0) begin
          state <= savedNextState;
        end
        else begin
          currentCore <= currentCore + 1;
          coresToInvalidate <= {1'b0, coresToInvalidate[12:1]};
        
          if (coresToInvalidate[0] & (currentCore != opCore)) begin
            state <= writeL2Entry;
            nextState <= invalidateL2Entries;
            opCore <= currentCore;
            opData <= 128'b0;
          end
        end
      end
      // --- End of L2 Cache and Memory Directory Operations ---
    
      setupMemDir: begin
        // Before starting to handle memory requests clear whole
        // memory directory and set appropriate initial values.
        //
        // Wait for ~memOpQempty because otherwise for some unknown reasons
        // DDR is sometimes not yet responsive. 
        // TODO: fix this waiting with something that makes more sense
        if (~memOpQempty & ~wbFull & ~afFull) begin          
          if (lineCnt == 24'h800000) begin
            state <= setupL2Cache;
            lineCnt <= 0;
          end else begin
            lineCnt <= lineCnt + 1;
            
            state <= writeMemDirEntry;
            nextState <= setupMemDir;
            opAddress <= {6'b0, lineCnt[22:0], 3'b0};
            if (lineCnt[22:4] == 0)
              opData <= 128'h000A000A000A000A000A000A000A000A;
            else 
              opData <= 128'b0;
          end
        end
      end
        
      setupL2Cache: begin
        // Setup L2 Cache entries for Core 1 for first 128 cache lines
        if (~wbFull & ~afFull) begin          
          if (lineCnt == 8'h80) begin
            state <= handleMemOp;
          end else begin
            lineCnt <= lineCnt + 1;
        
            state <= writeL2Entry;
            nextState <= setupL2Cache;
            opCore <= 1;
            opAddress <= {25'b0, lineCnt[6:0]};
            opData <= {99'b0, 1'b1, 21'b0, lineCnt[6:0]};
          end
        end
      end
              
      handleMemOp: if (~memOpQempty) begin
        // handle Memory Operation
        if (memOpType == `Address & memOpData[28]) begin
          // Read Address memory operation
          if (memOpDest > `nCores | memOpData[25:23] == MEM_DIR_PREFIX) begin
            state <= returnRDonHit;
          end else begin
            // it is read request or an exclusive read request
            state <= readL2Entry;
            nextState <= checkL2Entry; 
            opCore <= memOpDest;
            opAddress <= memOpData;
          end
        end else if (memOpType == `Address & ~memOpData[28]) begin
          // Flush memory operation
          if (memOpData[25:23] == MEM_DIR_PREFIX) state <= skipWrite;                
          else begin
            if (memOpDest <= `nCores) begin
              state <= updateMemDirEntry;
              nextState <= writeDataToMemory;
              opAddress <= memOpData;
              opCore <= memOpDest;
              opEvictCore <= 0;
            end else begin
              state <= writeDataToMemory;
            end
          end
        end else if (memOpType == `DMCCachePush) begin
          state <= readMemDirEntry;
          nextState <= handleCachePush;
          opAddress <= {4'b0, memOpData[27:0]};
        end
      end

      // states for handling memory read      
      checkL2Entry: begin
        if (opData[27:0] == memOpData[27:0] & opData[28]) begin
          // L2 cache hit
          state <= returnRDonHit;
        end else begin
          // L2 cache Miss
          evictL2Entry <= opData[28];
          
          if (opData[28]) begin
            // first step is to evict the line from L2 cache
            state <= updateMemDirEntry;
            nextState <= handleL2Miss;
            opAddress <= {4'b0, opData[27:0]};
            opCore <= memOpDest;
            opEvictCore <= 1;
          end
          else begin
            state <= handleL2Miss;
          end
        end
      end
               
      // States for returning ReadData when L2 hit occurs      
      returnRDonHit: begin
        if (memOpData[30]) begin
          // if 30th bit of memOpData is set it means, core already has 
          // latest data just wanted exclusive permision on the data, 
          // i.e. changing from SHARED to MODIFIED      
          state <= updateMemDirEntry;
          nextState <= handleMemOpDone;
          opAddress <= memOpData;
          opCore <= memOpDest;
          opEvictCore <= 0;
        end
        else state <= returnRDonHit_1;
      end
      
      returnRDonHit_1: if (~rbEmpty) state <= returnRDonHit_2;
      
      returnRDonHit_2: if (~rbEmpty) begin
        if (memOpDest <= `nCores & memOpData[25:23] != MEM_DIR_PREFIX &
            memOpData[29]) begin
          // for read exclusive request need to update memory directory entry
          state <= updateMemDirEntry;
          nextState <= handleMemOpDone;
          opAddress <= memOpData;
          opCore <= memOpDest;
          opEvictCore <= 0;
        end else begin
          state <= handleMemOpDone;
        end
      end
            
      // States for handling L2 miss      
      handleL2Miss: begin
        state <= readMemDirEntry;
        nextState <= handleL2Miss_1;
        opAddress <= memOpData;
      end
      
      handleL2Miss_1: begin
        // check directory entry if read is possible
        if ((memDirEntry[1:0] == MEM_CLEAN) | 
            (memDirEntry[1:0] == MEM_WAITING & memOpData[31])) begin
          // read is possible
          state <= updateMemDirEntry_2;
          nextState <= handleL2Miss_2;
          opAddress <= memOpData;
          opCore <= memOpDest;
          opEvictCore <= 0;
          
          L2CTCMiss <= (memDirEntry[15:2] != 0);
        end
        else begin
          // if read is not possible resend the read request
          // also if we evicted an address make sure to clear the L2 entry
          if (evictL2Entry) begin
            state <= writeL2Entry;
            nextState <= resendOnMiss;
            opAddress <= memOpData;
            opCore <= memOpDest;
            opData <= 128'b0;
          end else begin
            state <= resendOnMiss;
          end
        end
      end
      
      handleL2Miss_2: begin
        state <= writeL2Entry;
        nextState <= returnRDonMiss;
        opAddress <= memOpData;
        opCore <= memOpDest;
        opData <= {99'b0, 1'b1, memOpData[27:0]};
      end
      
      resendOnMiss: state <= handleMemOpDone;
      
      // States for returning ReadData when L2 miss occurs            
      returnRDonMiss: state <= returnRDonMiss_1;
      returnRDonMiss_1: if (~rbEmpty) state <= returnRDonMiss_2;
      returnRDonMiss_2: if (~rbEmpty) state <= handleMemOpDone;
      
      // States for handling flushes
      writeDataToMemory: if (~writeDataQempty) state <= writeDataToMemory_1;
      writeDataToMemory_1: if (~writeDataQempty) state <= handleMemOpDone;
      
      skipWrite: if (~writeDataQempty) state <= skipWrite_1;
      skipWrite_1: if (~writeDataQempty) state <= handleMemOpDone;
      
      // States for handling Cache Pushes
      handleCachePush: begin
        if (((memDirEntry[15:2] & (1 << memOpDest)) == 0) |
            ((memDirEntry[15:2] & (1 << memOpData[31:28])) != 0)) begin
          state <= handleMemOpDone;
        end else begin
          state <= updateMemDirEntry_2;
          nextState <= handleCachePush_1;
          opCore <= memOpData[31:28];
          opAddress <= {4'b0001, memOpData[27:0]};
          opEvictCore <= 0;
        end
      end
      
      handleCachePush_1: begin
        state <= readL2Entry;
        nextState <= handleCachePush_2;
        opCore <= memOpData[31:28];
        opAddress <= {4'b0000, memOpData[27:0]};
      end
      
      handleCachePush_2: begin
        if (~opData[28]) begin
          state <= (opData[27:0] == memOpData[27:0]) ? handleMemOpDone : 
                                                       handleCachePush_3;
        end else begin
          state <= updateMemDirEntry;
          nextState <= handleCachePush_3;
          opCore <= memOpData[31:28];
          opAddress <= {4'b0000, opData[27:0]};
          opEvictCore <= 1;
        end
      end
      
      handleCachePush_3: begin
        state <= writeL2Entry;
        nextState <= handleMemOpDone;
        opCore <= memOpData[31:28];
        opAddress <= {4'b0000, memOpData[27:0]};
        opData <= {99'b0, 1'b1, memOpData[27:0]};
      end
      
      handleMemOpDone: state <= handleMemOp;
    endcase
  end
  
  wire [3:0] RDdestOnHit = 
    ((~rbEmpty) & 
     (state == returnRDonHit_1 | 
      state == returnRDonHit_2)) ? memOpDest : 4'b0;
  RDDelayer #(.DELAY_CYCLES(DELAY_ON_HIT)) DelayOnHit(
    .clock(clock),
    .reset(reset),
    .RD(readData),
    .dest(RDdestOnHit),
    .rdDelayedRD(rdDelayedRDonHit),
    .delayedRD(delayedRDonHit),
    .delayedDest(delayedRDdestOnHit));

  wire [3:0] RDdestOnMissCTC = 
    ((~rbEmpty) & (L2CTCMiss) &
     (state == returnRDonMiss_1 | 
      state == returnRDonMiss_2)) ? memOpDest : 4'b0;
  RDDelayer #(.DELAY_CYCLES(DELAY_ON_MISS_CTC)) DelayOnMissCTC(
    .clock(clock),
    .reset(reset),
    .RD(readData),
    .dest(RDdestOnMissCTC),
    .rdDelayedRD(rdDelayedRDonMissCTC),
    .delayedRD(delayedRDonMissCTC),
    .delayedDest(delayedRDdestOnMissCTC));

  wire [3:0] RDdestOnMissMemory =
    ((~rbEmpty) & (~L2CTCMiss) &
     (state == returnRDonMiss_1 | 
      state == returnRDonMiss_2)) ? memOpDest : 4'b0;
  RDDelayer #(.DELAY_CYCLES(DELAY_ON_MISS_MEMORY)) DelayOnMissMemory(
    .clock(clock),
    .reset(reset),
    .RD(readData),
    .dest(RDdestOnMissMemory),
    .rdDelayedRD(rdDelayedRDonMissMemory),
    .delayedRD(delayedRDonMissMemory),
    .delayedDest(delayedRDdestOnMissMemory));

  // Output RDreturn and RDdest.
  assign rdDelayedRDonHit = 
    (delayedRDdestOnHit != 0);
  assign rdDelayedRDonMissCTC = 
    ~rdDelayedRDonHit && (delayedRDdestOnMissCTC != 0);
  assign rdDelayedRDonMissMemory = 
    ~rdDelayedRDonHit && ~rdDelayedRDonMissCTC && 
    (delayedRDdestOnMissMemory != 0);
                        
  assign RDreturn = rdDelayedRDonHit       ? delayedRDonHit         : 
                    rdDelayedRDonMissCTC    ? delayedRDonMissCTC    : 
                    rdDelayedRDonMissMemory ? delayedRDonMissMemory : 32'b0;
              
  assign RDdest  = rdDelayedRDonHit        ? delayedRDdestOnHit        : 
                   rdDelayedRDonMissCTC    ? delayedRDdestOnMissCTC    : 
                   rdDelayedRDonMissMemory ? delayedRDdestOnMissMemory : 4'b0;
endmodule
