`timescale 1ns / 1ps
/*
  Memory Model FSM.
  This FSM supports coherent DCaches using a directory based cache coherence.
  Directory is instantiated in RAM. Also simulates coherent L2 cache for each 
  core. L2 cache data is also located in RAM.
  
  Created By: Zviad Metreveli
*/

module mmsFSMcoherentL2_v1 (
  input clock,
  input reset,
  
  // mem op queue
  input memOpQempty,
  output reg rdMemOp,
  input [3:0] memOpDest,
  input [3:0] memOpType,
  input [31:0] memOpData,

  // mem op write data queue
  input writeDataQempty,
  output reg rdWriteData,
  input[127:0] writeDataIn,
  
  // resend queue
  output reg wrResend,
  output reg [39:0] resendOut,
  
  // wires from DDR read data buffer
  input rbEmpty,
  output reg rdRB,
  input [127:0] readData,
    
  // wires to DDR controller
  input wbFull,
  input afFull,
  output reg wrAF,
  output reg [25:0] afAddress,
  output reg afRead,
  output reg wrWB,
  output reg [127:0] writeData,

  // RD outputs  
  output [31:0] RDreturn,  //separate path for read data return
  output [3:0] RDdest,
  
  output reg [127:0] RDtoDC,
  output reg wrRDtoDC
);

  parameter DELAY_ON_HIT         = 0;     // Delay on L2 HIT
  parameter DELAY_ON_MISS_CTC    = 1000;  // Delay on L2 Cache To Cache Miss
  parameter DELAY_ON_MISS_MEMORY = 2000;  // Delay on L2 Miss

  // we need 2^26 entries, each 16 bits.
  // TODO: explain this more
  localparam MEM_DIR_PREFIX = {3'b011};

  // memory directory entry states
  localparam MEM_CLEAN    = 0;
  localparam MEM_WAITING  = 1;
  localparam MEM_MODIFIED = 2;
  
  // L2 cache entries. The entries are overlapping some of the
  // memory directory entries, however this is ok since
  // this are directory entries for directory entry addresses
  // thus they are not used.
  // Each core has it's own L2 cache, entry of address X of core C
  // is located at {L2_ENTRY_PREFIX, X[LOG_CACHE_LINES-1:0], C}
  parameter LOG_CACHE_LINES = 16;
  parameter L2_PREFIX = {MEM_DIR_PREFIX, MEM_DIR_PREFIX};
  
  // RDs for hit
  reg [127:0] RDonHit;  
  reg [3:0] RDdestOnHit;
  // RDs for miss from memory
  reg [127:0] RDonMissMemory;  
  reg [3:0] RDdestOnMissMemory;  
  // RDs for miss CTC
  reg [127:0] RDonMissCTC;  
  reg [3:0] RDdestOnMissCTC;

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
  
  // memory directory entry and update wires
  wire [15:0] memDirEntry, newMemDirEntry;
  wire [1:0] newState;
  wire [3:0] opDestShift;
  wire [127:0] updateDirEntry, evictL2UpdateDirEntry, flushUpdateDirEntry;
      
  // FSM state and next_state
  reg [4:0] state, next_state;
  reg doUpdateDirEntry, set_doUpdateDirEntry;
  reg [28:0] evictAddress, set_evictAddress;
  reg [13:0] coresToInvalidate, set_coresToInvalidate;
  reg [3:0] currentCore, set_currentCore;
  // counter for clearing mem directory initially
  reg [23:0] dirClearLine, set_dirClearLine;
  
  //FSM States
  localparam idle = 0; 
  localparam handleMemOp = 1;
  localparam checkL2Entry = 2;
  localparam returnRDonHit_clearRB = 3;
  localparam returnRDonHit_1 = 4;
  localparam returnRDonHit_2 = 5;
  localparam updateDirectoryEntry_1 = 6;
  localparam updateDirectoryEntry_2 = 7;
  localparam evictL2Entry_clearRB = 8;
  localparam evictL2Entry = 9;
  localparam fetchL2Entry_clearRB = 10;
  localparam fetchL2Entry = 11;
  localparam resendRead_clearRB = 12;
  localparam returnRDonMiss_clearRB = 13;
  localparam returnRDonMiss_1 = 14;
  localparam returnRDonMiss_2 = 15;
  localparam invalidateL2Entries_1 = 16;
  localparam invalidateL2Entries_2 = 17;
  localparam writeDataToMemory = 18;
  localparam flushUpdateDirectoryEntry_1 = 19;
  localparam flushUpdateDirectoryEntry_2 = 20;
  localparam skipWrite = 21;
  localparam returnRDtoDC_1 = 22;
  localparam returnRDtoDC_2 = 23;
  
//---------------------End of Declarations-----------------
    
  // memory directory entry for current memory operation
  assign memDirEntry = (readData >> ({memOpData[2:0], 4'b0000}));
                      
  // newState, depending on Request:
  // read - MEM_CLEAN
  // exclusive read - MEM_MODIFIED
  // flush - MEM_CLEAN
  // request flush - MEM_WAITING
  assign newState = (memOpData[29:28] == 2'b00) ? MEM_CLEAN : 
              (memOpData[29:28] == 2'b01) ? MEM_CLEAN : 
              (memOpData[29:28] == 2'b10) ? MEM_WAITING : 
                                  MEM_MODIFIED;
  
  // When flushing just need to set the state of the entry to newState
  assign flushUpdateDirEntry = 
    (readData & ~(2'b11 << {memOpData[2:0], 4'b0000})) | 
    (newState << {memOpData[2:0], 4'b0000});
                            
  // When finishing read/exclusive read in addition to updating state need 
  // to set the bit for the core in memory directory entry. if exclusive read 
  // we need to clear all other bits
  assign newMemDirEntry = 
    memOpData[29] ? {(1 << memOpDest[3:0]), newState} : 
                    {(1 << memOpDest[3:0]) | memDirEntry[15:2], newState};
  assign updateDirEntry = 
    (readData & ~(16'hFFFF << {memOpData[2:0], 4'b0000})) | 
    (newMemDirEntry << {memOpData[2:0], 4'b0000});
  
  // when evicting L2 entry just need to unset the bit corresponding to the 
  // core for evictAddress
  assign opDestShift = memOpDest + 2; // plus 2 since size of state is 2 bits
  assign evictL2UpdateDirEntry = 
    readData & ~(1 << {evictAddress[2:0], opDestShift});
  
  // State Machine
  always @(posedge clock) begin
    if (reset) begin
      state <= idle;
      dirClearLine <= 0;
      doUpdateDirEntry <= 0;
    end
    else begin
      state <= next_state; 
      dirClearLine <= set_dirClearLine;
      doUpdateDirEntry <= set_doUpdateDirEntry;
      evictAddress <= set_evictAddress;
      coresToInvalidate <= set_coresToInvalidate;
      currentCore <= set_currentCore;
    end
  end
  
  // State Machine outputs and next state calculation
  always @(*) begin
    // default values
    next_state = state;
    set_dirClearLine = dirClearLine;
    set_doUpdateDirEntry = doUpdateDirEntry;
    set_evictAddress = evictAddress;
    set_coresToInvalidate = coresToInvalidate;
    set_currentCore = currentCore;
    
    // memOpQ and writeDataQ
    rdMemOp = 0;
    rdWriteData = 0;
    // resendQ
    wrResend  = 0;
    resendOut = 0;
    
    // DDR address & read buffer & write buffer
    wrAF = 0;
    afAddress = 0;    
    afRead = 0;
    rdRB = 0;
    wrWB = 0;
    writeData = 0;
    
    // RDs on hit and miss
    RDdestOnHit = 0;
    RDonHit = 0;
    RDdestOnMissCTC = 0;
    RDonMissCTC = 0;
    RDdestOnMissMemory = 0;
    RDonMissMemory = 0;
    
    // RD to Display Controller
    wrRDtoDC = 0;
    RDtoDC = 0;
          
    case(state)
      idle: begin
        // Before starting to handle memory requests clear whole
        // memory directory and set appropriate initial values.
        // Also set appropriate 
        // Wait for ~memOpQempty because otherwise for some unknown reasons
        // DDR is sometimes not yet responsive. 
        // TODO: probably fix this waiting with something that makes more sense
        if (~memOpQempty && ~wbFull && ~afFull) begin          
          if (dirClearLine == 24'hFFFFFF) next_state = handleMemOp;
          set_dirClearLine = dirClearLine + 1;
          
          wrWB = 1;
          if (~dirClearLine[0] && dirClearLine[23:5] == 0)
            // first 128 lines are in modified state
            writeData = 128'h000A000A000A000A000A000A000A000A;
          else if (~dirClearLine[0] && dirClearLine[4:1] == 4'h1 && 
                   dirClearLine[23:21] == MEM_DIR_PREFIX && 
                   dirClearLine[20:12] == 0)
            // core 1 L2 cache first 128 lines are valid
            writeData = {99'b0, 1'b1, 21'b0, dirClearLine[11:5]};
          else
            writeData = 128'b0;
          
          if (dirClearLine[0]) begin
            wrAF = 1;
            afRead = 0;
            afAddress = {MEM_DIR_PREFIX, dirClearLine[23:1]};
          end
        end
      end
      
      handleMemOp: begin
        if (~memOpQempty) begin
          // handle Memory Operation          
          if (memOpDest[3:0] == 0) begin
            // Display Controller read hack
            next_state = returnRDtoDC_1;
            wrAF = 1;
            afRead = 1;
            afAddress = memOpData[25:0];            
          end
          else begin
            if (memOpData[28]) begin                            
              if (memOpDest <= `nCores && 
                  memOpData[25:23] != MEM_DIR_PREFIX) begin
                // it is read or an exclusive read request
                next_state = checkL2Entry; 
                wrAF = 1;
                afRead = 1;
                afAddress = 
                  {L2_PREFIX, memOpData[LOG_CACHE_LINES - 1:0], memOpDest};
              end
              else begin
                next_state = returnRDonHit_1;
                wrAF = 1;
                afRead = 1;
                afAddress = memOpData[25:0];
              end
            end
            else if (~writeDataQempty) begin                
              // it is a flush request
              if (memOpData[25:23] == MEM_DIR_PREFIX) begin
                // Do not allow writes to memory directory locations
                next_state = skipWrite;
                rdWriteData = 1;                
              end
              else begin
                next_state = writeDataToMemory; 

                if (memOpDest <= `nCores) begin
                  wrAF = 1;
                  afRead = 1;
                  afAddress = {MEM_DIR_PREFIX, memOpData[25:3]};
                end
                
                // write data to the write buffer
                rdWriteData = 1;
                wrWB = 1;
                writeData = writeDataIn;
              end              
            end
          end
        end
      end

      // states for handling memory read      
      checkL2Entry: begin
        if (~rbEmpty) begin
          rdRB = 1;
          
          if (readData[27:0] == memOpData[27:0] && readData[28]) begin
            // L2 cache hit
            next_state = returnRDonHit_clearRB;
            if (~memOpData[30]) begin
              // ask ddr to read value from memory
              wrAF = 1;
              afRead = 1;
              afAddress = memOpData[25:0];
            end 
            else begin
              // if 30th bit of memOpData is set it means, core already has 
              // latest data just wanted exclusive permision on the data, 
              // i.e. changing from SHARED to MODIFIED
              wrResend = 1;
              resendOut = 
                {memOpDest, `GrantExclusive, 4'b0000, memOpData[27:0]};
            end              
          end
          else begin
            // L2 cache Miss
            set_evictAddress = readData[28:0];
            
            if (readData[28]) begin
              // first step is to evict the line from L2 cache
              next_state = evictL2Entry_clearRB;
              wrAF = 1;
              afRead = 1;
              afAddress = {MEM_DIR_PREFIX, readData[25:3]};
            end
            else begin
              // if no need for eviction, we need to check the directory              
              next_state = fetchL2Entry_clearRB;
              wrAF = 1;
              afRead = 1;
              afAddress = {MEM_DIR_PREFIX, memOpData[25:3]};
            end
          end          
        end
      end
                  
      // States for Outputing RDonHit, when L2 hit occurs
      returnRDonHit_clearRB: begin
        if (~rbEmpty) begin
          rdRB = 1;
          if (~memOpData[30]) begin
            // we need to return RD
            next_state = returnRDonHit_1;
          end
          else begin
            if (memOpData[29]) begin
              // if it is read exclusive need to update directory entry
              next_state = updateDirectoryEntry_1;
            end
            else begin
              next_state = handleMemOp;
              rdMemOp = 1;
            end
          end
          
          if (memOpData[29]) begin
            wrAF = 1;
            afRead = 1;
            afAddress = {MEM_DIR_PREFIX, memOpData[25:3]};
          end
        end
      end
      
      returnRDonHit_1: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = returnRDonHit_2;
          
          RDonHit = readData;
          RDdestOnHit = memOpDest;
        end
      end
      
      returnRDonHit_2: begin
        if (~rbEmpty) begin
          rdRB = 1;
          
          if (memOpData[29] && memOpDest <= `nCores && 
              memOpData[25:23] != MEM_DIR_PREFIX) begin
            next_state = updateDirectoryEntry_1;
          end
          else begin
            next_state = handleMemOp;
            rdMemOp = 1;
          end
          
          RDonHit = readData;
          RDdestOnHit = memOpDest;
        end
      end
      
      updateDirectoryEntry_1: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = updateDirectoryEntry_2;
          set_coresToInvalidate = memDirEntry[15:2];
          set_currentCore = 0;
          
          wrWB = 1;
          writeData = updateDirEntry;
        end
      end

      updateDirectoryEntry_2: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = invalidateL2Entries_1;
          
          wrWB = 1;
          writeData = 128'b0;
          
          wrAF = 1;
          afRead = 0;
          afAddress = {MEM_DIR_PREFIX, memOpData[25:3]};
        end
      end
      
      // states for handling L2 miss
      evictL2Entry_clearRB: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = evictL2Entry;
          
          // read directory entry for memOp address
          // to check and handle miss
          wrAF = 1;
          afRead = 1;
          afAddress = {MEM_DIR_PREFIX, memOpData[25:3]};
        end
      end
      
      evictL2Entry: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = fetchL2Entry_clearRB;          
          
          wrWB = 1;
          writeData = evictL2UpdateDirEntry;
        end
      end
      
      fetchL2Entry_clearRB: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = fetchL2Entry;
          
          if (evictAddress[28]) begin
            // need to finish eviction
            wrWB = 1;
            writeData = 128'b0;
            
            wrAF = 1;
            afRead = 0;
            afAddress = {MEM_DIR_PREFIX, evictAddress[25:3]};
          end
        end
      end
      
      fetchL2Entry: begin
        if (~rbEmpty) begin
          rdRB = 1;
          
          // check directory entry if read is possible
          if ((memDirEntry[1:0] == MEM_CLEAN) || 
              (memDirEntry[1:0] == MEM_WAITING && memOpData[31])) begin
            // read is possible
            next_state = returnRDonMiss_clearRB;
            set_coresToInvalidate = memDirEntry[15:2];   

            // read data from DDR memory
            wrAF = 1;
            afRead = 1;
            afAddress = memOpData[25:0];
            
            // update directory entry
            wrWB = 1;
            writeData = updateDirEntry;            
          end
          else begin
            // if read is not possible resend the read request
            next_state = resendRead_clearRB; 
            wrResend = 1;
            resendOut = {memOpDest, `Address, 2'b10, memOpData[29:0]};
            
            if (evictAddress[28]) begin
              // if we evicted data, however failed to read need to
              // invalidate l2 entry that was evicted
              wrWB = 1;
              writeData = 128'b0;
            end
          end
        end
      end
      
      resendRead_clearRB: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = handleMemOp;
          rdMemOp = 1;
          
          if (evictAddress[28]) begin
            // finish invalidating l2 entry
            wrWB = 1;
            writeData = 128'b0;
            
            wrAF = 1;
            afRead = 0;
            afAddress = 
              {L2_PREFIX, memOpData[LOG_CACHE_LINES - 1:0], memOpDest};
          end
        end
      end
      
      returnRDonMiss_clearRB: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = returnRDonMiss_1;
          
          wrWB = 1;
          writeData = 128'b0;
          
          wrAF = 1;
          afRead = 0;
          afAddress = {MEM_DIR_PREFIX, memOpData[25:3]};
        end
      end
      
      returnRDonMiss_1: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = returnRDonMiss_2;
          
          wrWB = 1;
          writeData = {99'b0, 1'b1, memOpData[27:0]};
          
          if (coresToInvalidate == 0) begin
            RDonMissMemory = readData;
            RDdestOnMissMemory = memOpDest;
          end
          else begin
            RDonMissCTC = readData;
            RDdestOnMissCTC = memOpDest;
          end
        end
      end
      
      returnRDonMiss_2: begin
        if (~rbEmpty) begin
          rdRB = 1;
          if (coresToInvalidate == 0 || ~memOpData[29]) begin
            next_state = handleMemOp;
            rdMemOp = 1;
          end
          else begin
            next_state = invalidateL2Entries_1;
            set_currentCore = 0;
          end
          
          wrWB = 1;
          writeData = 128'b0;
          
          wrAF = 1;
          afRead = 0;
          afAddress = 
            {L2_PREFIX, memOpData[LOG_CACHE_LINES - 1:0], memOpDest};
          
          if (coresToInvalidate == 0) begin
            RDonMissMemory = readData;
            RDdestOnMissMemory = memOpDest;
          end
          else begin
            RDonMissCTC = readData;
            RDdestOnMissCTC = memOpDest;
          end
        end
      end

      invalidateL2Entries_1: begin      
        if (coresToInvalidate == 0) begin
          next_state = handleMemOp;
          rdMemOp = 1;
        end
        else begin
          set_currentCore = currentCore + 1;
          set_coresToInvalidate = {1'b0, coresToInvalidate[13:1]};
        
          if (coresToInvalidate[1] && (currentCore + 1 != memOpDest)) begin
            next_state = invalidateL2Entries_2;
            wrWB = 1;
            writeData = 128'b0;
          end
          else begin
            next_state = invalidateL2Entries_1;
          end
        end
      end
      
      invalidateL2Entries_2: begin
        next_state = invalidateL2Entries_1;

        wrWB = 1;
        writeData = 128'b0;
        
        wrAF = 1;
        afRead = 0;
        afAddress = 
          {L2_PREFIX, memOpData[LOG_CACHE_LINES - 1:0], currentCore};
      end      
      
      // States for handling memory write
      writeDataToMemory: begin
        if (~writeDataQempty) begin
          if (memOpDest <= `nCores) 
            next_state = flushUpdateDirectoryEntry_1;
          else begin
            next_state = handleMemOp;
            rdMemOp = 1;
          end
                   
          // add write data to write buffer
          rdWriteData = 1;          
          wrWB = 1;
          writeData = writeDataIn;
          
          // schedule write to memory
          wrAF = 1;
          afAddress = memOpData[25:0];
          afRead = 0;
        end
      end

      flushUpdateDirectoryEntry_1: begin
        if (~rbEmpty) begin
          next_state = flushUpdateDirectoryEntry_2;
          rdRB = 1;          
                    
          wrWB = 1;
          writeData = flushUpdateDirEntry;
        end
      end
      
      flushUpdateDirectoryEntry_2: begin
        if (~rbEmpty) begin
          next_state = handleMemOp;
          rdRB = 1;
          rdMemOp = 1;
                    
          wrWB = 1;
          writeData = 128'b0;
          // update directory entry
          wrAF = 1;
          afAddress = {MEM_DIR_PREFIX, memOpData[25:3]};
          afRead = 0;
        end
      end
      
      skipWrite: begin
        if (~writeDataQempty) begin  
          next_state = handleMemOp;
          rdMemOp = 1;
          rdWriteData = 1;
        end
      end
      
      // States for Outputing RDtoDC
      returnRDtoDC_1: begin
        if (~rbEmpty) begin
          next_state = returnRDtoDC_2;
          rdRB = 1;
          wrRDtoDC = 1;
          RDtoDC = readData;
        end
      end
      
      returnRDtoDC_2: begin
        if (~rbEmpty) begin
          next_state = handleMemOp;
          rdMemOp = 1;          
          rdRB = 1;
          wrRDtoDC = 1;
          RDtoDC = readData;
        end
      end
    endcase
  end
  
  RDDelayer #(.DELAY_CYCLES(DELAY_ON_HIT)) DelayOnHit(
    .clock(clock),
    .reset(reset),
    .RD(RDonHit),
    .dest(RDdestOnHit),
    .rdDelayedRD(rdDelayedRDonHit),
    .delayedRD(delayedRDonHit),
    .delayedDest(delayedRDdestOnHit));

  RDDelayer #(.DELAY_CYCLES(DELAY_ON_MISS_CTC)) DelayOnMissCTC(
    .clock(clock),
    .reset(reset),
    .RD(RDonMissCTC),
    .dest(RDdestOnMissCTC),
    .rdDelayedRD(rdDelayedRDonMissCTC),
    .delayedRD(delayedRDonMissCTC),
    .delayedDest(delayedRDdestOnMissCTC));

  RDDelayer #(.DELAY_CYCLES(DELAY_ON_MISS_MEMORY)) DelayOnMissMemory(
    .clock(clock),
    .reset(reset),
    .RD(RDonMissMemory),
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
