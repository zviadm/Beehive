/*
  Global Constants File
  All Global constants should be defined in this file
  
  Created By: Zviad Metreveli
*/

`default_nettype none

// Define SlotTypes
`define StartUp        4'd0
`define Token          4'd1
`define Address        4'd2
`define WriteData      4'd3
`define GrantExclusive 4'd6
`define Null           4'd7
`define Message        4'd8
`define Preq           4'd9
`define Pfail          4'd10
`define Vreq           4'd11
`define Barrier        4'd12
