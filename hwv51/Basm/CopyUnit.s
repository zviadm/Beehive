
// © Copyright Microsoft Corporation, 2008, 2009

/* This is the code for the SimpleRisc connected to the block copy unit.
It uses word addressing, and doesn't contain a multiplier or a lock unit.
The data memory is not a cache (just a 1K RAM), and the instruction memory
is a 1KW ROM.
*/

//register names:
void   = $0
t1     = $1
t2     = $2
t3     = $3

SA     = $4
DA     = $5
L      = $6


Checksum = $8
MsgHdr   = $9
Temp   = $13
Addr   = $15


/*
Index     = $3  //Registers used by the Ethernet controller
FrameAddr = $4
TxHead = $5
TxTail = $6
RxHdrPtr = $7
Status   = $8
MsgHdr   = $9
Eflags    = $10
arriving = 0x01  //Eflags bits
newAddr  = 0x02
gotFrame = 0x04  //set on first received frame
mcstOK   = 0x08  //accept multicast packets
mcst     = 0x10  //incoming packet is multicast
MAChigh = $11
MAClow  = $12
RxHdr2 = $14
Temp2  = $16
SMAC0  = $17
SMAC1  = $18
*/

CoreID = $19
LowHalf = $20

/* The six registers below are only used by the shell, which will not run
after the Ethernet is started.
*/
Base   = $10  
K      = $11
Char   = $12
Total  = $14
Flags  = $16
N      = $17

ma1    = $21
ma2    = $22
md1    = $23
md2    = $24
count  = $25
IObase = $26
zero    = $27
stkp    = $28

F_idec    = 0x01   // input in decimal
F_odec    = 0x02   // output in decimal
F_open    = 0x04   // cell is open
F_Nvalid  = 0x08   // N is valid

// ------------------------------------------------------------
// Data segment
// ------------------------------------------------------------
    data
decwords = 10
hexwords = 8

dectable: 
	word 1
	word 10
	word 100
	word 1000
	word 10000
	word 100000
	word 1000000
	word 10000000
	word 100000000
	word 1000000000


hextable: 
	word 1
	word 0x10
	word 0x100
	word 0x1000
	word 0x10000
	word 0x100000
	word 0x1000000
	word 0x10000000


// ------------------------------------------------------------
// Memory mapped IO definitions
// ------------------------------------------------------------
    abs    0x80000000
IO_:
IO_ASLI: blkw 1

// ------------------------------------------------------------
// Code segment
// ------------------------------------------------------------
    code
    word     0
start:
    andn     zero, zero, zero // initialize zero
    assume   zero, 0          // henceforth assume it
    long_ld  IObase, IO_      // initialize IObase
    assume   IObase, IO_      // henceforth assume it
    ld 	 stkp, 127		   // initialize stkp
	
// ------------------------------------------------------------
// Shell initialization.
// ------------------------------------------------------------
shell:
    ld       N, 0
    ld       Flags, F_idec|F_odec
    aqr_ld   void, IO_ASLI
    ld       CoreID, rq
    lsr      CoreID, CoreID, 10
	 
    j        copyTest   //skip the shell.

shellPrompt:
    call     printCRLF
    ld       N, CoreID
    call     printNum
    ld       Char, ">"
    call     printCh
    
    
// ------------------------------------------------------------
// Read and process command character.
// ------------------------------------------------------------
chLoop:
    aqr_ld   void, IO_ASLI           
    ld       Char, rq               // Read RS232
    lsr      CoreID, Char, 10
    and      void, Char, 0x100      // Test for receiver full
    jz       chLoop                 // not Full...
    ld       wq, 0x100              // Reenable the receiver
    aqw_ld   void, IO_ASLI
    and      Char, Char, 0x7f       // Mask to 7 bits
    sub      void, Char, "/";   jz openCellHexOut
    sub      void, Char, "\\";  jz openCellDecOut
    sub      void, Char, ">";   jz nextCell
    sub      void, Char, "<";   jz prevCell
    sub      void, Char, 13;    jz closeCell
    sub      void, Char, "x";   jz hexData
    sub      void, Char, "g";   jz go
    sub      void, Char, "r";   jz release
    sub      void, Char, "0";   jm chLoop   // Char must be >= "0"...
    sub      void, Char, "9"+1; jm digitDec // have digit 0-9
    sub      void, Char, "a";   jm chLoop   // must be >= "a"...
    sub      void, Char, "f"+1; jm digitHex // have digit a-f
    j        chLoop



// ------------------------------------------------------------
// Input a digit (either hex or decimal)
// ------------------------------------------------------------
digitHex:
    sub      t3, Char, "a"-10       // save numerical value in t3
    and      void, Flags, F_idec    // decimal mode for input?
    jnz      chLoop                 // yes, so hex is not valid...
    j        digit.hexmode

digitDec:
    sub      t3, Char, "0"          // value numerical value in t3
    and      void, Flags, F_idec    // decimal mode for input?
    jz       digit.hexmode          // no...
    lsl      t1, N, 1               // X2
    lsl      N, N, 3                // X8
    add      N, N, t1               // X10 = X8 + X2
    j        digit.add
    
digit.hexmode:
    lsl      N, N, 4                // X16
digit.add:
    and      void, Flags, F_Nvalid  // already N valid?
    jnz      digit.keepN            // yes...
    ld       N, 0                   // initialize N to 0
    or       Flags, Flags, F_Nvalid // set N valid
digit.keepN:
    add      N, N, t3               // add numerical value to N
    call     printCh                // echo char
    j        chLoop

openCellHexOut:
    andn     Flags, Flags, F_odec
    j        openCell
    
openCellDecOut:
    or       Flags, Flags, F_odec
    
openCell:
    call     printCh                // echo the character
    ld       Char, " "
    call     printCh
    and      void, Flags, F_Nvalid  // is N valid?
    jz       openCellAtAddr         // no, keep same address...
    ld       Addr, N                // N is the address
    
openCellAtAddr:
    aqr_ld   void, Addr
    or       Flags, Flags, F_open   // set cellOpen
    ld       N, rq                  // cell contents
    call     printNum               // printNum prints N
    ld       Char, " "
    call     printCh
    andn     Flags, Flags, F_Nvalid // clear N valid
    j        chLoop

hexData:
    add      void, N, 0			// is N zero?
    jnz      chLoop                 // yes, cannot change input radix...
    andn     Flags, Flags, F_idec
    call     printCh
    j        chLoop

nextCell:
    ld       t3, datawordsize           // t3 = delta
    j        changeCell

prevCell:
    ld       t3, -datawordsize          // t3 = delta

// If the cell is open, go to the next or prev cell, but
// first write N into the current cell if N is valid.
//    t3 = the address delta
// ------------------------------------------------------------
changeCell:
    and      void, Flags, F_open    // cell open?
    jz       chLoop                 // no...
    
    and      void, Flags, F_Nvalid  // Nvalid?
    jz       changeCell.nostore     // no...

    ld       wq, N
    aqw_ld   void, Addr             // store N in address
changeCell.nostore:
    add      Addr, Addr, t3         // Addr += delta
    call     printCh                // echo
    call     printCRLF
    ld       Char, ">"
    call     printCh
    
    ld       N, Addr                // printNum prints N
    call     printNum               // print the address
    
    ld       Char, "\\"             // Predict that output radix is decimal
    and      void, Flags, F_odec
    jnz      changeCell.radix       // yes...
    ld       Char, "/"              // Prediction was wrong
changeCell.radix:
    call     printCh
    ld       Char, " "
    call     printCh
    j        openCellAtAddr
    
closeCell:
    and      void, Flags, F_open    // cell must be open to close 
    jz       shell
    and      void, Flags, F_Nvalid  // is N valid?
    jz       shell        		 // nothing entered...
    ld       wq, N
    aqw_ld   void, Addr             // store value at address
    j        shell    

// ------------------------------------------------------------
// Print a number
//    N = value to print
// Kills:
//    t1, t2, t3, Total, K, Base, Char
// ------------------------------------------------------------
printNum:
    ld       wq, link
    aqw_sub  stkp, stkp, datawordsize   //push the link
    ld       Total, 0               // total of all digits printed
    ld       K, hexwords            // assume hex mode
    long_ld  Base, hextable+(hexwords * datawordsize)
    and      void, Flags, F_odec    // test for hex out mode
    jz       printNum.digitloop     // yes...
    ld       K, decwords
    long_ld  Base, dectable+(decwords * datawordsize)
    ld       void, N                // Negative?
    jnm      printNum.digitloop
    sub      N, zero, N             // Negate
    ld       Char, "-"
    call     printCh

printNum.digitloop:
    // ----------------------------------------
    // Get the next smaller radix power into
    // t3 and compute the digit in Char
    // by repeated trial subtractions.
    // ----------------------------------------
    ld       Char, 0                // count number of subtracts
    aqr_sub  Base, Base, datawordsize   // get next smaller radix power
    ld       t3, rq
    
printNum.trialloop:
    // ----------------------------------------
    // Determine if N >= t3 in unsigned arithmetic.
    // This is true iff (N + ~t3 + 1) has a carryout.
    //
    // ----------------------------------------
    sub      t1, N, t3          // t1 = (N + ~t3 + 1)
    jnc	printNum.trialdone	//N >= t3, reduce it.    
    sub      N, N, t3
    add      Char, Char, 1
    j        printNum.trialloop
printNum.trialdone:
    add      Total, Total, Char   // add up total digits
    jz       printNum.digitnext   // suppress leading zeros...
    add      Char, Char, "0"      // Predict char is 0-9
    sub      void, Char, "0"+10
    jm       printNum.nohexadj    // yes, no need to hex adjust...
    add      Char, Char, "a"-"0"-10
printNum.nohexadj:
    // ----------------------------------------
    // Print the digit character.
    // ----------------------------------------
    call     printCh
    
printNum.digitnext:
    sub      K, K, 1
    jnz      printNum.digitloop   // do next digit...
    ld       void, Total          // all zero?
    jnz      return               // nope, return...
    ld       Char, "0"
    call     printCh
    
// Subroutine return sequence: Pop return address from stack.
// ------------------------------------------------------------
return:
    aqr_ld   void, stkp
    add      stkp, stkp, datawordsize
    j        rq

// ------------------------------------------------------------
// Print a character
//    Char = character to print
// Kills:
//    t1, t2, t3
// ------------------------------------------------------------
printCh:
    ld       wq, link
    aqw_sub  stkp, stkp, datawordsize   // push link
    
printCh.loop:
    aqr_ld   void, IObase
    ld       t1, rq
    and      t1, t1, 0x200          // transmitter empty?
    jz       printCh.loop           // yes, loop...
    
    or       wq, Char, t1           // write char OR transmit bit
    aqw_ld   void, IObase
    j        return

// ------------------------------------------------------------
// Print CR LF sequence
// Kills:
//    t1, t2, t3, Char
// ------------------------------------------------------------
printCRLF:
    ld       wq, link
    aqw_sub  stkp, stkp, datawordsize   // push link
    
    ld       Char, 13;  call printCh
    ld       Char, 10;  call printCh
    j        return

go:
    call     N                      // go
    j        shellPrompt

release:
    aqw_add  void, IObase, (2*datawordsize)
    ld       wq, 1
    aqw_add  void, IObase, (2*datawordsize)
    ld       wq, zero
    j        shellPrompt

//Test block copy.
copyTest:
   aqr_add  void, IObase, 4 //read the message queue
	ld       MsgHdr, rq      //should be zero (empty)
	jz       loop //releaseRS232 (don't need to release, since we never get it)
	ld       N, MsgHdr       //print what we got
	call     printNum
	j        start
	
releaseRS232:
   aqw_add  void, IObase, (2*datawordsize) //release the RS232
    ld       wq, 1
    aqw_add  void, IObase, (2*datawordsize)
    ld       wq, zero


loop:
   aqr_add  void, IObase, 4   //read the message queue
   ld       MsgHdr, rq
	jz       loop              //loop if empty
//MsgHdr has the length in bits 5:0 and the source core in bits 13:10.
//the length should be 3.
   and   Temp, MsgHdr, 0x7f
   sub   void, Temp, 3
   jz    .+2
   j     .     //halt
   lsr   MsgHdr, MsgHdr, 10  //the source core
   ld    wq, rq  //S
   ld    wq, rq  //D
   ld    wq, rq  //L
xfer:
   aqw_add   void,  IObase, 1  //IO device 1. DMA unit
   aqw_add   void, IObase, 0x9
   aqw_add  void,  IObase, 0x11
   ld       void, void //one cycle nop before reading device
checkBusy:
   aqr_add  void, IObase, 1
   ror      Checksum, rq, 1
   jm       checkBusy
   ld       wq, Checksum  //send it back to the client
   lsl      Temp, MsgHdr, 3     //the requesting core into bits 3:6 (message destination) 
   or       Temp, Temp, 0x84    //length = 1, I/O device 4 (messenger)
   aqw_add void, IObase, Temp //send the message
   j     loop


     
        