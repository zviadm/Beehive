`timescale 1ns / 1ps

module queue32(
 input clk,
 input [31 : 0] din,
 input rd_en,
 input rst,
 input wr_en,
 output [31 : 0] dout,
 output empty,
 output full
);

reg [5:0] ra, wa, cnt;

assign empty = (ra == wa);
assign full = cnt == 6'b111111;

always @(posedge clk)
 if(rst) cnt <= 0;
 else if(rd_en & ~wr_en) cnt <= cnt - 1;
 else if(~rd_en & wr_en) cnt <= cnt + 1;
 
always @(posedge clk) begin
 if(rst) ra <= 0;
 else if (rd_en) ra <= ra + 1;
end

always @(posedge clk) begin
 if(rst) wa <= 0;
 else if (wr_en) wa <= wa + 1;
end

genvar i;
generate
 for (i = 0; i < 32; i = i+1)
 begin: ram
   dpram qram(.CLK(clk), .in(din[i]), .out(dout[i]), .ra(ra), .wa(wa), .we(wr_en));
 end
endgenerate
endmodule
