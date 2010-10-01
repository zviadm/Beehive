// this file replaces RISCsrc/RISCtop.v for simulation
`timescale 1ns / 1ps
//`default_nettype none

// fifo of specified width and depth
module fifo #(parameter width = 1, logsize = 6, lut = 1) (
  input clk,
  input [width-1:0] din,
  input rd_en,
  input rst,
  input wr_en,
  output [width-1:0] dout,
  output empty,
  output full
  );

  localparam SIZE = 1 << logsize;

  reg [logsize-1:0] ra, wa, count;

  assign full = (count > (SIZE-4));
  assign empty = (count == 0);

  always @(posedge clk) begin
    if (rst) count <= 0;
    else if (rd_en & ~wr_en) count <= count - 1;
    else if (wr_en & ~rd_en) count <= count + 1;
  end

  wire [logsize-1:0] next_ra = rst ? 0 : rd_en ? ra+1 : ra;
  always @(posedge clk) begin
    ra <= next_ra;
  end

  always @(posedge clk) begin
    if (rst) wa <= 0;
    else if (wr_en) wa <= wa + 1;
  end

  generate
    if (logsize <= 6) begin
      (* ram_style = "distributed" *)
      reg [width-1:0] qram[SIZE-1:0];
      reg [logsize-1:0] qramAddr;
      always @(posedge clk) begin
        qramAddr <= next_ra;
        if (wr_en) qram[wa] <= din;
      end
      assign dout = qram[qramAddr];
    end
    else begin
      (* ram_style = "block" *)
      reg [width-1:0] qram[SIZE-1:0];
      reg [logsize-1:0] qramAddr;
      always @(posedge clk) begin
        qramAddr <= next_ra;
        if (wr_en) qram[wa] <= din;
      end
      assign dout = qram[qramAddr];
    end
  endgenerate
endmodule

// display rs232 serial stream on simulation console
// special hack: writing 0x7F stops the simulation
module rs232_sim #(parameter bitTime = 868) (input clock,reset,RxD);
  reg [10:0] bitCounter;  // counts modulo bitTime
  reg [9:0] sr;  // where received bits are accumulated
  reg run;   // 1 if we've seen START bit

  // count if we see START bit or if in middle of receiving
  wire runCounter = ~RxD | run;

  wire midBit = bitCounter == bitTime/2;

  always @(posedge clock) begin
    bitCounter <= 
      (runCounter & (bitCounter < (bitTime - 1))) ? bitCounter + 1 : 0;

    if (reset) run <= 0;
    else if (~RxD & midBit & ~run) run <= 1;  // START bit? start receiving
    else if (sr[0]) run <= 0;  // stop receiving when STOP bit enters sr

    if (reset | (~run & sr[0])) sr <= 0;
    else if (midBit & ~sr[0]) sr[9:0] <= {~RxD,sr[9:1]};  // right shift

    // output character we've received
    if (~run & sr[0]) case (~sr[8:1])
      default: $write("\\x%x",~sr[8:1]);
      8'h09: $write("\t");
      8'h0A: $write("\n");
      8'h0D: $write("");    // don't bother with CR
      8'h20: $write(" ");
      8'h21: $write("!");
      8'h22: $write("\"");
      8'h23: $write("#");
      8'h24: $write("$");
      8'h25: $write("%%");
      8'h26: $write("&");
      8'h27: $write("'");
      8'h28: $write("(");
      8'h29: $write(")");
      8'h2A: $write("*");
      8'h2B: $write("+");
      8'h2C: $write(",");
      8'h2D: $write("-");
      8'h2E: $write(".");
      8'h2F: $write("/");
      8'h30: $write("0");
      8'h31: $write("1");
      8'h32: $write("2");
      8'h33: $write("3");
      8'h34: $write("4");
      8'h35: $write("5");
      8'h36: $write("6");
      8'h37: $write("7");
      8'h38: $write("8");
      8'h39: $write("9");
      8'h3A: $write(":");
      8'h3B: $write(";");
      8'h3C: $write("<");
      8'h3D: $write("-");
      8'h3E: $write(">");
      8'h3F: $write("?");
      8'h40: $write("@");
      8'h41: $write("A");
      8'h42: $write("B");
      8'h43: $write("C");
      8'h44: $write("D");
      8'h45: $write("E");
      8'h46: $write("F");
      8'h47: $write("G");
      8'h48: $write("H");
      8'h49: $write("I");
      8'h4A: $write("J");
      8'h4B: $write("K");
      8'h4C: $write("L");
      8'h4D: $write("M");
      8'h4E: $write("N");
      8'h4F: $write("O");
      8'h50: $write("P");
      8'h51: $write("Q");
      8'h52: $write("R");
      8'h53: $write("S");
      8'h54: $write("T");
      8'h55: $write("U");
      8'h56: $write("V");
      8'h57: $write("W");
      8'h58: $write("X");
      8'h59: $write("Y");
      8'h5A: $write("Z");
      8'h5B: $write("[");
      8'h5C: $write("\\");
      8'h5D: $write("]");
      8'h5E: $write("^");
      8'h5F: $write("_");
      8'h60: $write("`");
      8'h61: $write("a");
      8'h62: $write("b");
      8'h63: $write("c");
      8'h64: $write("d");
      8'h65: $write("e");
      8'h66: $write("f");
      8'h67: $write("g");
      8'h68: $write("h");
      8'h69: $write("i");
      8'h6A: $write("j");
      8'h6B: $write("k");
      8'h6C: $write("l");
      8'h6D: $write("m");
      8'h6E: $write("n");
      8'h6F: $write("o");
      8'h70: $write("p");
      8'h71: $write("q");
      8'h72: $write("r");
      8'h73: $write("s");
      8'h74: $write("t");
      8'h75: $write("u");
      8'h76: $write("v");
      8'h77: $write("w");
      8'h78: $write("x");
      8'h79: $write("y");
      8'h7A: $write("z");
      8'h7B: $write("{");
      8'h7C: $write("|");
      8'h7D: $write("}");
      8'h7E: $write("~");
      8'h7F: $finish(0);
    endcase
    $fflush(1);
  end
endmodule

// fifo of specified width and depth
module beehive;
  localparam nCores = 3;  //Number of RISC cores in the design
  localparam MBITS = 24;  //log2(Size) of main memory (must match Master.s)
  localparam bitTime = 20;  // fast serial transmit when simulating

  reg clock;
  reg reset;
  reg [31:0] mem[0:(1 << MBITS)-1];

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
  localparam sendInitialToken = 0; // start a token on the ring this cycle
  localparam idle = 1; // empty queue onto the ring
  
  reg state;
  wire [31:0] mctrlRingIn     = RingOut[nCores];
  wire [3:0]  mctrlSlotTypeIn = SlotTypeOut[nCores];
  wire [3:0]  mctrlSourceIn   = SourceOut[nCores];
  
  always @(posedge clock) begin
    if (reset) begin
      state <= sendInitialToken;
      RingOut[0]     <= 32'b0;
      SlotTypeOut[0] <= Null;
      SourceOut[0]   <= 4'h0;
    end else case (state)
      sendInitialToken: begin
        state <= idle;
        RingOut[0]     <= 32'b0;
        SlotTypeOut[0] <= Token;
        SourceOut[0]   <= 4'h0;
      end
      
      idle: begin
        RingOut[0]     <= mctrlRingIn;
        SlotTypeOut[0] <= mctrlSlotTypeIn;
        SourceOut[0]   <= mctrlSourceIn;
      end
    endcase
  end

  // count the numbers of cars of each type in the train
  reg [31:0] meters[15:0];
  always @(posedge clock)
    if (!reset) meters[mctrlSlotTypeIn] <= meters[mctrlSlotTypeIn] + 1;
  // initialize meters to zero
  integer m; initial for (m = 0; m < 16; m = m + 1) meters[m] = 0;

  // display interesting ring data
  //always @(posedge clock) 
  //  if (RingSlotType != Null) 
  //      $display("Ring: type=%x, dest=%x, data=%x",
  //                RingSlotType,RingSrcDest,RingData);

  //************************************
  // Memory
  //************************************

  // capture memory addresses arriving from the ring
  wire ma_wr = (mctrlSlotTypeIn == Address);
  wire ma_rd;
  wire ma_rw,ma_empty;
  wire [3:0] ma_dest;
  wire [27:0] ma_addr;
  wire ma_full, md_full;
  fifo #(.width(33),.logsize(9)) ma(
    .clk(clock),
    .rst(reset),
    .din({mctrlSourceIn, mctrlRingIn[28:0]}),
    .wr_en(ma_wr),
    .dout({ma_dest, ma_rw, ma_addr}),
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
    if (ma_wr & ma_full) $display("*** write to full md fifo");

  // read and write 8-word blocks from memory (a cache line)
  // use a 4-bit counter, mcount == 8 when memory is idle
  reg [3:0] mcount;
  // memory needs to delay reads by 10 cycles to avoid breaking D cache
  reg [3:0] mdelay; 
   
  wire rd_enb = !reset & ma_rw & (mcount < 8);
  wire [MBITS-1:0] rd_addr = {ma_addr[MBITS-4:0],mcount[2:0]};
  wire rd_meters = (ma_addr[27:1] == -1);
  wire [31:0] rd_return =  rd_meters ? meters[rd_addr[3:0]] : mem[rd_addr];
  wire [3:0] rd_dest = rd_enb ? ma_dest : 0;

  always @(posedge clock) begin
    // complain if address falls outside range we cover
    if (!reset && mcount < 8 && !rd_meters && ma_addr[27:MBITS-3]!=0) 
      $display("**** ma_addr not valid: %x",ma_addr);
    
    RDreturn[0] <= (rd_dest == 0) ? 32'hDEADBEEF : rd_return;
    RDdest[0] <= rd_dest;
    //if (rd_dest != 0) 
    //  $display("r mem[%x] %x core %x",rd_addr,rd_return,rd_dest);
    if (reset) begin
      mcount <= 4'h8;
      mdelay <= 4'h0;
    end
    else if (!ma_empty && mcount == 8 && mdelay == 0) begin
      if (ma_rw) mdelay <= 10;  // only delay on reads
      else mcount <= 0;
    end
    else if (!ma_empty && mcount == 8 && mdelay != 0) begin
      mdelay <= mdelay - 1;
      if (mdelay == 1) mcount <= 0;
    end
    else if (mcount < 8) begin
      if (!ma_rw) begin   // write
        mem[rd_addr] <= md_data;
        //$display("w mem[%x] %x",rd_addr,md_data);
      end
      mcount <= mcount + 1;
    end
  end

  assign md_rd = (mcount < 8) & !ma_rw;
  assign ma_rd = (mcount == 7);

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
  wire exeN = 
    !beehive.coreBlk[N].riscN.nullify & !beehive.coreBlk[N].riscN.stall;
  always @(negedge clock) if (!reset) begin
    /*
    if (cycle_count <= 1000) begin
      $write("cycle=%5d ",cycle_count);
      //$write("pcx=%x ",beehive.coreBlk[N].riscN.pcx);
      //$write("instx=%x ",beehive.coreBlk[N].riscN.instx);
      $write("pc=%x ",beehive.coreBlk[N].riscN.pc);
      $write("inst=%x ",beehive.coreBlk[N].riscN.inst);
      $write("outx=%x ",beehive.coreBlk[N].riscN.outx);
      $write("out=%x/%x ",beehive.coreBlk[N].riscN.out,beehive.coreBlk[N].riscN.wwq);
      $write("n/s=%x/%x ",beehive.coreBlk[N].riscN.nullify,beehive.coreBlk[N].riscN.stall);
      $write("lock_ring_in=%x ",beehive.coreBlk[N].riscN.lockUnit.RingIn);
      $write("lock_aq_=%x ",beehive.coreBlk[N].riscN.lockUnit.aq);
      //$write("aq=%x/%x/%x ",beehive.coreBlk[N].riscN.aqrd,beehive.coreBlk[N].riscN.aq,beehive.coreBlk[N].riscN.aqe);
      //$write("wq=%x/%x%x%x ",beehive.coreBlk[N].riscN.wq,|beehive.coreBlk[N].riscN.rwq,beehive.coreBlk[N].riscN.wwq,beehive.coreBlk[N].riscN.wqe);
      //$write("wq: %x%x%x %x %x %x ",beehive.coreBlk[N].riscN.writeQueue.rst,beehive.coreBlk[N].riscN.writeQueue.rd_en,beehive.coreBlk[N].riscN.writeQueue.wr_en,beehive.coreBlk[N].riscN.writeQueue.ra,beehive.coreBlk[N].riscN.writeQueue.wa,beehive.coreBlk[N].riscN.writeQueue.count);
      //$write("state=%x ",beehive.coreBlk[N].riscN.lockUnit.state);
      //$write("locked=%x ",beehive.coreBlk[N].riscN.lockUnit.locked);
      //$write("rqe=%x ",beehive.coreBlk[N].riscN.rqe);
      //$write("Ihit=%x ",beehive.coreBlk[N].riscN.Ihit);
      //$write("writeDTag=%x ",beehive.coreBlk[N].riscN.dCacheN.writeDtag);
      //$write("web=%x ",beehive.coreBlk[N].riscN.dCacheN.web);
      //$write("cnt=%x ",beehive.coreBlk[N].riscN.dCacheN.cnt);
      //$write("state=%x ",beehive.coreBlk[N].riscN.dCacheN.state);
      //$write("lineCnt=%x ",beehive.coreBlk[N].riscN.dCacheN.lineCnt);
      //$write("[1] pc=%x/%x/%x ",beehive.coreBlk[1].riscN.pc,beehive.coreBlk[1].riscN.nullify,beehive.coreBlk[1].riscN.stall);
      //$write("[2] pc=%x/%x/%x ",beehive.coreBlk[2].riscN.pc,beehive.coreBlk[2].riscN.nullify,beehive.coreBlk[2].riscN.stall);
      //$write("[3] pc=%x/%x/% ",beehive.coreBlk[3].riscN.pc,beehive.coreBlk[3].riscN.nullify,beehive.coreBlk[3].riscN.stall);
      $write("Ring: type=%x, dest=%x, data=%x ", mctrlSlotTypeIn, mctrlSourceIn, mctrlRingIn);
      $write("RDreturn=%x, RDdest=%x ",rd_return,rd_dest);
      $display("");
    end */
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
    $readmemh("../Simulation/main.hex", mem);

    // deassert reset after ring has cleared (ncores*10 + 5 time units)
    #135
    reset = 0;
  end

  // clock with period 10
  always #5 clock = ~clock;
endmodule
