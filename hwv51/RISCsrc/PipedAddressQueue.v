`timescale 1ns / 1ps

module PipedAddressQueue(
 input clk,
 input [32 : 0] din,
 input rd_en,
 input rst,
 input wr_en,
 output reg [32 : 0] dout,
 output empty,
 input decLineAddr
);

/* This 33 x 64-entry queue has a pipeline stage (dout) between the RAM and the output. The design
includes an additional feature:  If decLineCnt is presented, it causes bits 9:3 of the dout register
to increment.  This is used in invalidating and flushing the Dcache.  It allows the address to come
from a register rather than going through an addr, improving the timing.

The bypassing is tricky.  The following table should make it clear(er).  doutFull' is
the value of dqFull after the clock.  We bypass the queue whenever doutFull = 0:

case	wr_en rd_en   ldDout    doutFull' incRA   incWA
____________________________________________________
1       0       0  |  0       doutFull   0        0
2       0       1  |~RQempty  ~RQempty ~RQempty   0
3       1       0  |~doutFull     1      0      doutFull
4       1       1  |  1       doutFull ~RQempty ~RQempty

In case 1, nothing changes.

In case 2, we are reading from a non-empty queue (it must nonempty, or the consumer would not
issue the read).  The entire queue becomes empty (doutFull == 0) if RQ is empty. RA is incremented
only if ~RQempty. WA is unchanged.

In case 3, we load dout only if ~doutFull. If doutFull, WA is incremented. RA is unchanged.

In case 4, doutFull and RQempty don't change, so RA and WA must either both increment (~RQempty),
or neither increments.

RQ is written whenever WA is incremented.   
*/

(* KEEP = "TRUE" *) wire RQempty;
reg  doutFull;
wire ldDout;
wire incRA;
wire incWA;
wire [32:0] RQout; //output of the RAM

reg [5:0] ra, wa;

//--------------------End of declarations-----------------------------

assign RQempty = (ra == wa);

assign empty = ~doutFull;  //Output to the client

assign ldDout = (~wr_en & rd_en & ~RQempty) | (wr_en & ~rd_en & ~doutFull) | (wr_en & rd_en); 

assign incRA =  (~wr_en & rd_en & ~RQempty) | (wr_en & rd_en & ~RQempty); 

assign incWA =  (wr_en & ~rd_en & doutFull) | (wr_en & rd_en & ~RQempty);

always @(posedge clk) if(ldDout) dout <= RQempty ? din : RQout;  //bypass if RQempty.
  else if(decLineAddr) dout[9:3] <= dout[9:3] + 1;

always @(posedge clk) if(rst) doutFull <= 0;
  else begin
    if(~wr_en & rd_en) doutFull <= ~RQempty;
	 else if (wr_en & ~rd_en) doutFull <= 1;
	 //else doutFull <= doutFull 
  end
 
always @(posedge clk) begin
 if(rst) ra <= 0;
 else if (incRA) ra <= ra + 1;
end

always @(posedge clk) begin
 if(rst) wa <= 0;
 else if (incWA) wa <= wa + 1;
end

genvar i;
generate
 for (i = 0; i < 33; i = i+1)
 begin: ram
   dpram64 qram(.CLK(clk), .in(din[i]), .out(RQout[i]), .ra(ra), .wa(wa), .we(incWA));
 end
endgenerate


endmodule
