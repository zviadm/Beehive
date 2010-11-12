/*
  Global Constants File
  All Global constants should be defined in this file
  
  Created By: Zviad Metreveli
*/

`default_nettype none

`define nCores         4'd3
`define EtherCore      `nCores + 4'd1
`define CopyCore       `nCores + 4'd2

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
`define DMCHeader      4'd13
`define DMCAddress     4'd14
`define DMCData        4'd15
