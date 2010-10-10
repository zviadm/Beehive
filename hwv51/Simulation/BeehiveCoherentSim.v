// this file replaces RISCsrc/RISCtop.v for coherent simulation
`timescale 1ns / 1ps

module beehiveCoherent;
  localparam nCores = 3;  //Number of RISC cores in the design
  localparam MBITS = 24;  //log2(Size) of main memory (must match Master.s)
  localparam bitTime = 20;  // fast serial transmit when simulating

  reg clock;
  reg reset;
  reg [31:0] mem[0:(1 << MBITS)-1];
  reg [1:0] mem_dir[0:(1 << (MBITS - 3)) - 1];

  // Memory Directory Entry Values
  localparam MEM_CLEAN    = 0;
  localparam MEM_WAITING  = 1;
  localparam MEM_MODIFIED = 2;

  //************************************
  // Cores
  //************************************

  //The registers of the ring
  reg [31:0] RingOut[nCores:0];
  reg [3:0]  SlotTypeOut[nCores:0];
  reg [3:0]  SourceOut[nCores:0];

  reg [31:0] RDreturn[nCores:0];  //separate pipelined bus for read data
  reg [3:0]  RDdest[nCores:0];

  wire [nCores:1] releaseRS232;
  wire [nCores:1] lockHeld;
  wire [nCores:1] TxDv;
  wire [nCores:1] RxDv;

  wire [3:0] etherCore = nCores+1;
  wire [3:0] copyCore = nCores+2;

  //instantiate the RISC cores
  genvar i;
  generate
    for (i = 1; i <= nCores; i = i+1) begin: coreBlk
      wire [31:0] tempRiscRingOut;
      wire [3:0] tempRiscSlotTypeOut;
      wire [3:0] tempRiscSourceOut;
      wire [3:0] coreNum = i;

      RISC #(.bitTime(bitTime),
             .I_INIT(i==1 ? "../Simulation/Mastercode.hex" : 
                            "../Simulation/Slavecode.hex"),
             .D_INIT(i==1 ? "../Simulation/Masterdata.hex" : 
                            "../Simulation/Slavedata.hex"))
       riscN(
       .clock(clock),
       .reset(reset),
       .whichCore(coreNum),  //the number of this core
       .RingIn(RingOut[i-1]),
       .SlotTypeIn(SlotTypeOut[i-1]),
       .SourceIn(SourceOut[i-1]),
       .RDreturn(RDreturn[i-1]),
       .RDdest(RDdest[i-1]),
       .RingOut(tempRiscRingOut),
       .SlotTypeOut(tempRiscSlotTypeOut),
       .SourceOut(tempRiscSourceOut),
       .RxD(RxDv[i]),
       .TxD(TxDv[i]),
       //core connected to the RS232 pulses this to reset the selection
       .releaseRS232(releaseRS232[i]), 
       .EtherCore(etherCore),
       .CopyCore(copyCore)
      );

      always @(posedge clock) begin
        RDreturn[i] <= RDreturn[i-1];
        RDdest[i] <= RDdest[i-1];
      end

      always @(posedge clock) begin
        RingOut[i] <= tempRiscRingOut;
        SlotTypeOut[i] <= tempRiscSlotTypeOut;
        SourceOut[i] <= tempRiscSourceOut;
      end
    end
  endgenerate

  // for now, no incoming RS232 data to any core (hold RxD at one)
  assign RxDv = -1;

  // for now, just capture RS232 chars from Core 1 (the master)
  wire RxD = TxDv[1];

  //************************************
  // Ring processing
  //************************************

  // Slot types
  localparam Token = 1;     // data = count of following words
  localparam Address = 2;   // data = { 1'read, 28'line_addr }, source = node
  localparam WriteData = 3; // data => mem data fifo
  localparam Null = 7;

  // Interactions with the ring
  localparam dumpResendQ = 0; 
  localparam waitToken   = 1; 
  
  reg state;
  wire [31:0] mctrlRingIn     = RingOut[nCores];
  wire [3:0]  mctrlSlotTypeIn = SlotTypeOut[nCores];
  wire [3:0]  mctrlSourceIn   = SourceOut[nCores];
  
  always @(posedge clock) begin
    if (reset) begin
      state <= dumpResendQ;
      RingOut[0]     <= 32'b0;
      SlotTypeOut[0] <= Null;
      SourceOut[0]   <= 4'h0;
    end else case (state)
      dumpResendQ: begin
        if (resendQempty) begin
          state <= waitToken;
          RingOut[0]     <= 32'b0;
          SlotTypeOut[0] <= Token;
          SourceOut[0]   <= 4'h0;
        end else begin
          RingOut[0]     <= resendQout;
          SlotTypeOut[0] <= resendQtype;
          SourceOut[0]   <= resendQdest;
        end
      end
      
      waitToken: begin
        if (mctrlSlotTypeIn == Token) state <= dumpResendQ;
        
        if ((mctrlSlotTypeIn == Token) | 
            (mctrlSlotTypeIn == Address & mctrlRingIn[31])) begin
          RingOut[0]     <= 0;
          SlotTypeOut[0] <= Null;
          SourceOut[0]   <= 0;
        end else begin
          RingOut[0]     <= mctrlRingIn;
          SlotTypeOut[0] <= mctrlSlotTypeIn;
          SourceOut[0]   <= mctrlSourceIn;
        end
      end
    endcase
  end


  //************************************
  // Memory
  //************************************

  // resend queue wires
  wire [39:0] resendQin;
  wire wrResendQ;
  wire [3:0] resendQtype, resendQdest;
  wire [31:0] resendQout;
  wire resendQempty;

  wire rdResendQ = (state == dumpResendQ) & ~resendQempty;    
  resendQ resendQueue (
    .clk(clock),
    .rst(reset),
    .din(resendQin), // Bus [39 : 0] 
    .wr_en(wrResendQ),
    .rd_en(rdResendQ),
    .dout({resendQdest, resendQtype, resendQout}), // Bus [39 : 0] 
    .full(),
    .empty(resendQempty));


  // capture memory addresses arriving from the ring
  wire ma_wr = (mctrlSlotTypeIn == Address);
  wire ma_rd;
  wire ma_empty;
  wire [3:0] ma_dest;
  wire [31:0] ma_addr;
  wire ma_full;
  fifo #(.width(36),.logsize(9)) ma(
    .clk(clock),
    .rst(reset),
    .din({mctrlSourceIn, mctrlRingIn}),
    .wr_en(ma_wr),
    .dout({ma_dest, ma_addr}),
    .rd_en(ma_rd),
    .empty(ma_empty),
    .full(ma_full)
  );
  always @(posedge clock) 
    if (ma_wr & ma_full) $display("*** write to full ma fifo");

  // capture write data arriving from the ring
  wire md_wr = (mctrlSlotTypeIn == WriteData);
  wire md_rd;
  wire md_empty;
  wire [31:0] md_data;
  wire md_full;
  fifo #(.width(32),.logsize(12)) md(
    .clk(clock),
    .rst(reset),
    .din(mctrlRingIn),
    .wr_en(md_wr),
    .dout(md_data),
    .rd_en(md_rd),
    .empty(md_empty),
    .full(md_full)
  );
  always @(posedge clock) 
    if (md_wr & md_full) $display("*** write to full md fifo");

  // memory controller state machine
  reg [3:0] mem_state;
  localparam readAddress   = 0;
  localparam sendRD        = 1;
  localparam readWriteData = 2;
  
  // read and write 8-word blocks from memory (a cache line)
  // use a 4-bit counter, mcount == 8 when memory is idle
  reg [3:0] mcount;   
  
  wire [MBITS-1:0] rd_addr = {ma_addr[MBITS-4:0],mcount[2:0]};
  wire [31:0] rd_return = (mem_state == sendRD) ? mem[rd_addr] : 0;
  wire [3:0] rd_dest = (mem_state == sendRD) ? ma_dest : 0;

  wire readRA = (mem_state == readAddress) & ~ma_empty & ma_addr[28];
  wire readPossible = 
    (mem_dir[ma_addr[MBITS - 4:0]] == MEM_CLEAN) |
    (mem_dir[ma_addr[MBITS - 4:0]] == MEM_WAITING & ma_addr[31]);

  assign wrResendQ = 
    (readRA & readPossible & ma_addr[30]) | (readRA & ~readPossible);
  assign resendQin = 
    (readRA & readPossible & ma_addr[30]) ? 
      {ma_dest, 4'b0110, 4'b0000, ma_addr[27:0]} :
    (readRA & ~readPossible) ?
      {ma_dest, 4'b0010, 2'b10, ma_addr[29:0]} : 40'b0;

  always @(posedge clock) begin
    // complain if address falls outside range we cover
    if (!reset && mem_state == readAddress && 
        ~ma_empty && ma_addr[27:MBITS-3] != 0) 
      $display("**** ma_addr not valid: %x, ma_dest: %x", ma_addr, ma_dest);
    
    RDreturn[0] <= rd_return;
    RDdest[0] <= rd_dest;
    //if (rd_dest != 0) 
    //  $display("r mem[%x] %x core %x",rd_addr,rd_return,rd_dest);
    if (reset) begin
      mem_state <= readAddress;
      mcount <= 4'h8;
    end
    else case (mem_state)
      readAddress: if (~ma_empty) begin
        if (ma_addr[28]) begin
          if (readPossible) begin
            mem_dir[ma_addr[MBITS - 4:0]] <= 
              (ma_addr[29]) ? MEM_MODIFIED : MEM_CLEAN;
              
            if (~ma_addr[30]) begin
              mem_state <= sendRD;
              mcount <= 0;
            end
          end
        end else begin
          mem_dir[ma_addr[MBITS - 4:0]] <= 
              (ma_addr[29]) ? MEM_WAITING : MEM_CLEAN;        

          mem_state <= readWriteData;
          mcount <= 0;
        end
      end
      
      sendRD: begin
        if (mcount == 7) mem_state <= readAddress;
        mcount <= mcount + 1;
      end
        
      readWriteData: begin
        if (mcount == 7) mem_state <= readAddress;
        mcount <= mcount + 1;
        
        mem[rd_addr] <= md_data;
      end
    endcase    
  end

  assign md_rd = (mcount < 8) & (mem_state == readWriteData);
  assign ma_rd = 
    (mcount == 7) | 
    (readRA & (~readPossible | (readPossible & ma_addr[30])));

  //************************************
  // RS232 receiver (listens to RxD)
  //************************************

  rs232_sim #(.bitTime(bitTime)) ttyout(clock,reset,RxD);

  //************************************
  // Simulation control
  //************************************

  reg [31:0] cycle_count;
  always @(posedge clock) begin
    cycle_count <= reset ? 0 : cycle_count + 1;
  end   

  // periodically print out cycle count
  /*
  always @(posedge clock) if (!reset & (cycle_count % 10000) == 0) begin
    $display("");
    $write("*** cycle %d:",cycle_count);
    $write(" [core 1] pcx=%x",beehive.coreBlk[1].riscN.pcx);
    $write(" [core 2] pcx=%x",beehive.coreBlk[2].riscN.pcx);
    $write(" [core 3] pcx=%x",beehive.coreBlk[3].riscN.pcx);
    $display("");
  end
  */

  // follow execution in core N
  localparam N = 2;
  // true on cycles where core N is executing an instruction 
  // (not stalled, not anulled)
  //wire exeN = 
  //  !beehive.coreBlk[2].riscN.nullify & !beehive.coreBlk[N].riscN.stall;
  reg delayedSelDCache;
  always @(negedge clock) if (!reset) begin
    if (coreBlk[1].riscN.msgrN.msgrFifoFull == 1) begin
      $write("core 1 msgr Fifo Full");
      $display("");
    end
    if (coreBlk[2].riscN.msgrN.msgrFifoFull == 1) begin
      $write("core 2 msgr Fifo Full");
      $display("");
    end
    if (coreBlk[1].riscN.msgrN.msgrFifoFull == 1) begin
      $write("core 3 msgr Fifo Full");
      $display("");
    end
    /*
    if (mctrlSlotTypeIn != Null & mctrlSlotTypeIn != Token) begin
      $display("Ring: type=%x, dest=%x, data=%x",
                mctrlSlotTypeIn, mctrlSourceIn, mctrlRingIn);
    end */

    /*
    if (coreBlk[2].riscN.dCacheN.selDCache == 1) begin
      $write("cycle=%5d ", cycle_count);
      $write("pc=%x ", coreBlk[2].riscN.pc);
      $write("AQReadHit=%x ", coreBlk[2].riscN.dCacheN.AQReadHit);
      $write("AQWriteHit=%x ", coreBlk[2].riscN.dCacheN.AQWriteHit);
      $write("state=%x ", coreBlk[2].riscN.dCacheN.state);
      $write("waitReadDataState=%x ", coreBlk[2].riscN.dCacheN.waitReadDataState);
      $write("done=%x ", coreBlk[2].riscN.dCacheN.done);
      $write("RDreturn=%x, RDdest=%x ", coreBlk[2].riscN.dCacheN.RDreturn,
                                        coreBlk[2].riscN.dCacheN.RDdest);
      $write("NextCoreRingIn: SourceIn=%x, Type=%x, Ring=%x ", 
        coreBlk[3].riscN.SourceIn,
        coreBlk[3].riscN.SlotTypeIn,
        coreBlk[3].riscN.RingIn);      
      $display("");
    end
    */
        
    /*
    delayedSelDCache <= coreBlk[2].riscN.dCacheN.selDCache;
    if (//delayedSelDCache | coreBlk[2].riscN.dCacheN.dcDriveRing
        && coreBlk[2].riscN.dCacheN.aq[30:27] != 0
        (cycle_count > 174800 && cycle_count < 175000)) begin
      $write("cycle=%5d ",cycle_count);
      $write("pc=%x ",coreBlk[2].riscN.pc);
      $write("pcx=%x ",coreBlk[2].riscN.pcx);
      $write("inst=%x ",coreBlk[2].riscN.inst);
      $write("outx=%x ",coreBlk[2].riscN.outx);
      $write("out=%x/%x ",coreBlk[2].riscN.out,coreBlk[2].riscN.wwq);
      $write("n/s=%x/%x ",coreBlk[2].riscN.nullify,coreBlk[2].riscN.stall);
      $write("aq=%x/%x/%x ",coreBlk[2].riscN.aqrd,coreBlk[2].riscN.aq,coreBlk[2].riscN.aqe);
      $write("w=%x ",coreBlk[2].riscN.dCacheN.wq);
      $write("dcState=%x ",coreBlk[2].riscN.dCacheN.state);
      $write("ihit=%x ",coreBlk[2].riscN.dCacheN.Ihit);
      //$write("Ring: type=%x, source=%x, data=%x ",coreBlk[2].riscN.SlotTypeIn,
      //                                            coreBlk[2].riscN.SourceIn,
      //                                            coreBlk[2].riscN.RingIn);
      $write("MCTRL Ring: type=%x, src=%x, data=%x ", 
        mctrlSlotTypeIn, mctrlSourceIn, mctrlRingIn);
      $write("MCTRL RDreturn=%x, RDdest=%x ",rd_return,rd_dest);
      $display("");   
    end    
    */
    //if (cycle_count >= 84000) $finish(0);
  end

  integer k;
  initial begin
    //    $dumpfile("test.lxt");

    // capture top-level signals (ie, ring and memory buses)
    //$dumpvars(1,risc_test);
    // capture top-level of Master (core 1)
    //$dumpvars(1,beehive.coreBlk[1].riscN);
    // capture top-level of core 2
    //$dumpvars(1,beehive.coreBlk[2].riscN);

    clock = 1;
    reset = 1;

    // initialize lower part of main memory, assume high part doesn't need it
    for (k = 0; k < (1 << MBITS); k = k + 1) mem[k] = 32'hDEADBEEF;

    // initialize memory directory, first 128 lines are MODIFIED rest are CLEAN
    for (k = 0; k < 128; k = k + 1) mem_dir[k] = MEM_MODIFIED;
    for (k = 128; k < (1 << (MBITS - 3)); k = k + 1) mem_dir[k] = MEM_CLEAN;
    $readmemh("../Simulation/main.hex", mem);

    // deassert reset after ring has cleared (ncores*10 + 5 time units)
    #135
    reset = 0;
  end

  // clock with period 10
  always #5 clock = ~clock;
endmodule