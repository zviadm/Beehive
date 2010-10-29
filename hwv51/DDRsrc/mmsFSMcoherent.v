`timescale 1ns / 1ps

/*
   Memory Model FSM.
   This FSM supports coherent DCaches using a directory based cache coherence.
   Directory is instantiated in RAM.
   
   Created By: Zviad Metreveli
*/

module mmsFSMcoherent (
  input clock,
  input reset,

  // mem op queue
  input memOpQempty,
  output reg rdMemOp,
  input [3:0] memOpDest,
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

  parameter DELAY_ON_HIT = 0;

  // we need 2^26 entries, each 2 bits 
  localparam MEM_DIR_PREFIX = {6'b001111};
  localparam MEM_DIR_ENTRY_BITS = 2;

  localparam MEM_CLEAN = 0;
  localparam MEM_WAITING = 1;
  localparam MEM_MODIFIED = 2;

  // RDs for hit
  reg [127:0] RDonHit;  
  reg [3:0] RDdestOnHit;

  // wires from delayers
  wire rdDelayedRDonHit;
  wire [31:0] delayedRDonHit;
  wire [3:0] delayedRDdestOnHit;
       
  wire [1:0] memDirEntry;
  wire readPossible;
  wire [1:0] newState;
  wire [127:0] newStateMask, eraseEntryMask, updateDirEntry;
       
  // FSM state and next_state
  reg [3:0] state, next_state;
  reg doUpdateDirEntry, set_doUpdateDirEntry;

  // counter for clearing mem directory initially
  reg [20:0] dirClearLine, set_dirClearLine;

  //FSM States
  localparam idle = 0; 
  localparam handleMemOp = 1;
  localparam checkDirectoryEntry = 2;
  localparam returnRDonHit_clearRB = 3;
  localparam returnRDonHit_1 = 4;
  localparam returnRDonHit_2 = 5;
  localparam clearRB = 6;
  localparam clearRB_updateDirectoryEntry = 7;
  localparam writeDataToMemory = 8;
  localparam updateDirectoryEntry_1 = 9;
  localparam updateDirectoryEntry_2 = 10;
  localparam skipWrite = 11;
  localparam returnRDtoDC_1 = 12;
  localparam returnRDtoDC_2 = 13;
   
//---------------------End of Declarations-----------------
         
  // memory directory entry for current memory operation
  assign memDirEntry = (readData >> ({memOpData[5:0], 1'b0}));

  // read is possible if entry is in clean state or entry is in waiting
  // state and this is not a fresh read request
  assign readPossible = (memDirEntry == MEM_CLEAN) |
                        (memDirEntry == MEM_WAITING & memOpData[31]);
                              
  // newState, depending on Request:
  // read - MEM_CLEAN
  // exclusive read - MEM_MODIFIED
  // flush - MEM_CLEAN
  // request flush - MEM_WAITING
  assign newState = (memOpData[29:28] == 2'b00) ? MEM_CLEAN : 
                    (memOpData[29:28] == 2'b01) ? MEM_CLEAN : 
                    (memOpData[29:28] == 2'b10) ? MEM_WAITING : 
                                                  MEM_MODIFIED;
   
  // Wires for updating specific memory entry in 128 bit Read Data
  assign newStateMask = newState << ({memOpData[5:0], 1'b0});
  assign eraseEntryMask = ~(2'b11 << ({memOpData[5:0], 1'b0}));
  assign updateDirEntry = (readData & eraseEntryMask) + newStateMask; 

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
    end
  end
   
  // State Machine outputs and next state calculation
  always @(*) begin
    // default values
    next_state = state;
    set_dirClearLine = dirClearLine;
    set_doUpdateDirEntry = doUpdateDirEntry;
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
     
    // RD on hit
    RDdestOnHit = 0;
    RDonHit = 0;
      
    // RD to Display Controller
    wrRDtoDC = 0;
    RDtoDC = 0;
               
    case(state)
      idle: begin
        // Before starting to handle memory requests clear whole
        // memory directory and set appropriate initial values.
        // Wait for ~memOpQempty because otherwise for some unknown reasons
        // DDR is sometimes not yet responsive. 
        // TODO: probably fix this with something that makes more sense
        if (~memOpQempty && ~wbFull && ~afFull) begin               
          if (dirClearLine == 21'h1FFFFF) next_state = handleMemOp;
          set_dirClearLine = dirClearLine + 1;
          wrWB = 1;
          // first 127 lines are in modified state
          if (~dirClearLine[0] && dirClearLine[20:2] == 0)
            writeData = 128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
          else 
            writeData = 128'b0;
          
          if (dirClearLine[0]) begin
            wrAF = 1;
            afRead = 0;
            afAddress = {MEM_DIR_PREFIX, dirClearLine[20:1]};
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
                  memOpData[25:20] != MEM_DIR_PREFIX) begin
                // it is read or an exclusive read request
                next_state = checkDirectoryEntry; 
                wrAF = 1;
                afRead = 1;
                afAddress = {MEM_DIR_PREFIX, memOpData[25:6]};
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
              if (memOpData[25:20] == MEM_DIR_PREFIX) begin
                // Do not allow writes to memory directory locations
                // TODO: figure out a way to not have to do this
                next_state = skipWrite;
                rdWriteData = 1;                        
              end
              else begin
                next_state = writeDataToMemory; 
                 
                if (memOpDest <= `nCores) begin
                  wrAF = 1;
                  afRead = 1;
                  afAddress = {MEM_DIR_PREFIX, memOpData[25:6]};
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
      checkDirectoryEntry: begin
        if (~rbEmpty) begin
          rdRB = 1;
        
          // check directory entry
          if (readPossible) begin
            next_state = returnRDonHit_clearRB;
            if (~memOpData[30]) begin
              // ask ddr to read value from memory
              wrAF = 1;
              afRead = 1;
              afAddress = memOpData[25:0];
            end 
            else begin
              // if 30th bit of memOpData is set it means, core already has 
              // latest data just wanted exclusive permision on the data, i.e. 
              // changing from SHARED to MODIFIED
              wrResend = 1;
              resendOut = 
                {memOpDest, `GrantExclusive, 4'b0000, memOpData[27:0]};
            end
                
            if (newState != memDirEntry) begin
              set_doUpdateDirEntry = 1;
              // update directory entry
              wrWB = 1;
              writeData = updateDirEntry;
            end
            else begin
              set_doUpdateDirEntry = 0;
            end                  
          end
          else begin
            // if read is not possible resend the read request
            next_state = clearRB; 
            wrResend = 1;
            resendOut = {memOpDest, `Address, 2'b10, memOpData[29:0]};
          end
        end
      end
       
      clearRB: begin
        if (~rbEmpty) begin
          rdRB = 1;
          next_state = handleMemOp;
          rdMemOp = 1;
        end
      end
                
      // States for Outputing RDonHit
      returnRDonHit_clearRB: begin
        if (~rbEmpty) begin
          rdRB = 1;
          if (~memOpData[30]) next_state = returnRDonHit_1;
          else begin
            next_state = handleMemOp;
            rdMemOp = 1;
          end
        
          if (doUpdateDirEntry) begin
            // finish directory entry update
            wrWB = 1;
            writeData = 128'b0;

            wrAF = 1;
            afRead = 0;
            afAddress = {MEM_DIR_PREFIX, memOpData[25:6]};
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
          next_state = handleMemOp;
          rdMemOp = 1;
             
          RDonHit = readData;
          RDdestOnHit = memOpDest;
        end
      end
                
      // States for handling memory write
      writeDataToMemory: begin
        if (~writeDataQempty) begin
          if (memOpDest <= `nCores) 
            next_state = updateDirectoryEntry_1;
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

      updateDirectoryEntry_1: begin
        if (~rbEmpty) begin
          next_state = updateDirectoryEntry_2;
          rdRB = 1;               
      
          wrWB = 1;
          writeData = updateDirEntry;
        end
      end
       
      updateDirectoryEntry_2: begin
        if (~rbEmpty) begin
          next_state = handleMemOp;
          rdRB = 1;
          rdMemOp = 1;
                           
          wrWB = 1;
          writeData = 128'b0;
          // update directory entry
          wrAF = 1;
          afAddress = {MEM_DIR_PREFIX, memOpData[25:6]};
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
    .delayedDest(delayedRDdestOnHit)
  );

  // Output RDreturn and RDdest.
  assign rdDelayedRDonHit = (delayedRDdestOnHit != 0);
  assign RDreturn = delayedRDonHit;
  assign RDdest = delayedRDdestOnHit;
endmodule
