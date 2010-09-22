
`timescale 1ns/1ps

module queueN #(parameter width = 1)
 (
 input clk,
 input [width - 1 : 0] din,
 input rd_en,
 input rst,
 input wr_en,
 output [width -1 : 0] dout,
 output empty,
 output full
);


reg [5:0] ra, wa;
reg [5:0] count;

assign full = (count > 60);
assign empty = (count == 0);

always@(posedge clk) begin
 if(rst) count <= 0;
 else if(rd_en & ~wr_en) count <= count - 1;
 else if(wr_en & ~rd_en) count <= count + 1;
end
 
 
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
 for (i = 0; i < width; i = i+1)
 begin: ram
   dpram64 qram(.CLK(clk), .in(din[i]), .out(dout[i]), .ra(ra), .wa(wa), .we(wr_en));
 end
endgenerate
endmodule

