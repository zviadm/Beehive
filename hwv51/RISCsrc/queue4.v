`timescale 1ns / 1ps

module queue4(
 input clk,
 input [3: 0] din,
 input rd_en,
 input rst,
 input wr_en,
 output [3: 0] dout,
 output empty,
 output full
);

reg [5:0] ra, wa;

assign empty = (ra == wa);
assign full = 1'b0;

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
 for (i = 0; i < 4; i = i+1)
 begin: ram
   dpram qram(.CLK(clk), .in(din[i]), .out(dout[i]), .ra(ra), .wa(wa), .we(wr_en));
 end
endgenerate
endmodule
