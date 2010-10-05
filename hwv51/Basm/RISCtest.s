
// © Copyright Microsoft Corporation, 2008, 2009

/* This is the code for the SimpleRisc connected to the Ethernet controller.
It uses word addressing, and doesn't contain a multiplier or a lock unit.
The data memory is not a cache (just a 1K RAM), and the instruction memory
is a 1KW ROM.
*/

//register names:
void   = $0
t1     = $1
t2     = $2
t3     = $3

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
Temp   = $13
RxHdr2 = $14
Addr   = $15
Temp2  = $16
SMAC0  = $17
SMAC1  = $18
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

//The ethernet MAC base is written here by a human, and written into the EEPROM.
//At initialization, the controller reads it from the EEPROM and loads it into a register and into the hardware.	
macBase:
	.blkw 2   //msb (32 bits) in first word, lsb (16 bits) in second word.


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

    j        resetPhy  //Reset the PHY and start the controller. No shell needed

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
    sub	    void, Char, "r";  jz release
	 sub      void, Char, 0x20;  jz saveAddress  //EEPPROM address is in N
    sub      void, Char, "p";   jz printByte    //Print EEPROM byte at address N
	 sub      void, Char, "w";   jz writeByte    //write EEPROM byte to address N

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

resetPhy:
   aqw_add  void, IObase, (2 * datawordsize) //toggle phyReset
   ld       wq, 4
   ld       Temp, 0x3ff
resetDly:
   sub      Temp, Temp, 1
   jnz      resetDly  
   aqw_add  void, IObase, (2 * datawordsize)
   ld       wq, zero

// ------------------------------------------------------------
//The Ethernet controller
// ------------------------------------------------------------
controllerInit:
    long_ld  LowHalf, 0xffff  //a constant
/*
    aqw_add  void, IObase, (2 * datawordsize) //release the RS232
    ld       wq, 1
    aqw_add  void, IObase, (2 * datawordsize)
    ld       wq, zero
*/

//set up MAChigh and MAClow in the hardware.  Read the MAC address
//from the first 8 bytes of the EEPROM.
    ld      ma1, zero  //EEPROM address
	 ld      md2, 4     //loop count
	 call    pLoop
	 ld      MAChigh, md1     //word returned in md1
	 ld      md2, 4
	 call    pLoop
	 ld      MAClow, md1

   ld       wq, MAClow
   aqw_add  void, IObase, 0x0d //SMACaddr[15:4]
   ld       wq, MAChigh
   aqw_add  void, IObase, 0x05 //SMACaddr[47:16]
	
//store the data at macBase
   ld       wq, MAChigh
	aqw_long_ld   void, macBase
	ld       wq, MAClow
	aqw_long_ld  void, macBase + datawordsize

//Initialize the TxQ.  Starts at 256d, each entry is 32 words long
   ld      Addr, 256 - 32
   ld      count, 15
txInitLoop:
   add     wq, Addr, 64  //store Addr + 64
   aqw_add Addr, Addr, 32 //into Addr + 32, advance addr
   sub     count, count, 1
   jnz     txInitLoop
   ld      wq, 256       //last entry points to first
   aqw_add Addr, Addr, 32
   ld      TxHead, 256
   ld      TxTail, 256

//initialize the 32 word RxAddr array
   ld      count, 30  //array starts at 128. We go backwards
   ld      Addr, 128
rxAddrLoop:
   sub      wq, zero, 1  //entry is -1
   aqw_add  void, Addr, count
   sub      count, count, 2
   jnm      rxAddrLoop
   ld       RxHdrPtr, 768
   ld       Eflags, 0


// ------------------------------------------------------------
//initialization complete.  Main loop.
// ------------------------------------------------------------
checkHeaderReady:
   aqr_add  void, IObase, 0x9  //read controller status
   ror      Status, rq, 1      //HeaderReady is bit 0
   jm       doReceiveSetup
checkMsgArrived:
   aqr_add  void, IObase, 4   //read the message queue
   ld       MsgHdr, rq
   jnz      doProcessMsg
checkSendReady:
   sub      void, TxHead, TxTail  //see if TxQ has anything on it
   jnz      doSend
checkFrameArriving:
   and      void, Eflags, arriving
   jz       checkHeaderReady
checkFrameDone:
   aqr_add void, IObase, 0x9  //Read controller status
   ror     Status, rq, 1
   and      void, Status, 2    //frameLengthEmpty is now in bit 1
   jz       doReceiveCompletion
   j        checkMsgArrived
 
doReceiveSetup:
   aqr_ld void, RxHdrPtr           //read the first header word
   and    void, Eflags, mcstOK     //are we accepting multicast frames?
   jz     noMcst                   //no
   ld     Temp, rq                 //is this frame mulicast?
   jnm    noMcst + 1               //no
   aqr_add void, RxHdrPtr, 1       //start the read for the second header word
   or     Eflags, Eflags, mcst     //frame is multicast 
   ld     Index, 2                 //we will send the frame to core 1
   ld     RxHdr2, rq
   j      getSourceAddr

//if multicast isn't enabled or this is not a multicast frame,
//we filter the destination MAC address
noMcst:
   ld     Temp, rq
   andn   Eflags, Eflags, mcst    //not a multicast frame
   xor    void, Temp, MAChigh     //compare first word with high bits of MAC address
   jnz    dropFrame
   aqr_add void, RxHdrPtr, 1      //read the second header word
   ld     RxHdr2, rq
   lsr    Temp, RxHdr2, 20        //low 16 bits of MAC address RSH 4 into low half
   xor    void, Temp, MAClow      //compare with low bits of the MAC address
   jnz    dropFrame
   lsr    Index, RxHdr2, 15       //we need 2 * low bits to index the allocation table
   and    Index, Index, 0x1e      //save Index until packet is complete

//Get the source MAC address and EtherType and pack into two words.
//These are saved until the packet is complete.
getSourceAddr:
   aqr_add void, RxHdrPtr, 2      //bytes 2-5 of source MAC address
   aqr_add void, RxHdrPtr, 3      //EtherType in most significant half
   and    SMAC0, RxHdr2, LowHalf  //bytes 0, 1 of source MAC address into low half
   ld     SMAC1, rq               //bytes 2-5 of source MAC address
   andn   Temp2, rq, LowHalf
   or     SMAC0, SMAC0, Temp2     //OR EtherType and bytes 0,1 of source MAC address
     
   aqr_add void, Index, 128      //read the DMA address
   ld     FrameAddr, rq           //save FrameAddr until packet is complete
   jm     dropFrame               //drop if DMA address negative
   ld     wq, FrameAddr     
   or     Eflags, Eflags, arriving
   j      incHdrPtr

dropFrame:
   ld     wq, zero         //address == 0 => drop

incHdrPtr:
   add    RxHdrPtr, RxHdrPtr, 4  //increment header pointer
   and    void, RxHdrPtr, 0x3ff
   jnz    sendRxAddr      //check for overflow
   ld     RxHdrPtr, 768   //reset
sendRxAddr:
   aqw_add  void, IObase, 0x9   //send frame address to the DMA machine
   j     checkMsgArrived

doReceiveCompletion:
   aqr_add void, IObase, 0x1   //read the length (in bytes)
   andn   Eflags, Eflags, arriving //clear the "arriving" flag
   add_lsr     Temp, rq, zero, 2   //length in bytes (no badFrame/goodFrame bits
   lsr    Temp2, Temp, 5  //length in cache lines (almost).  Bytes/32
   and    void, Temp, 0x1f //did we need an additional cache line?
   jz    noExtras
   add    Temp2, Temp2, 1 //increment cache line length by 1
noExtras:
   and    void, Eflags, newAddr     //check whether a new address came in during reception
   jnz     sendRxMsg                //it did.  Don't update the DMA address
   aqr_add void, Index, 129         //read DMA limit
   add     Temp2, FrameAddr, Temp2  //next DMA address
   sub     void, rq, Temp2          //limit - new address
   jnm     update
   sub     Temp2, zero, 1           //limit exceeded.  Negate address to discard later frames
update:
   aqw_add void, Index, 128
   ld      wq, Temp2               //store updated address
sendRxMsg:
   andn    Eflags, Eflags, newAddr //clear Eflags.newAddr
   ld      wq, Temp                //length of received frame in bytes
   ld      wq, SMAC0
   ld      wq, SMAC1

   and     Temp, Eflags, mcst   //was this a multicast frame?
   ror     Temp, Temp, 5        //set msb if so.
   or      wq, FrameAddr, Temp
   lsl     Index, Index, 2       //destination core into bits 6:3
   or      Index, Index, 0x204   //message length = 4, IO device 4 (Messenger)
   aqw_add void, IObase, Index
   j       checkHeaderReady   //a non-nullified execution of this instruction is bad.

doProcessMsg:
//MsgHdr has the length in bits 5:0 and the source core in bits 13:10.
//If the message length is 1, it is a MAC address request.
//If it is 2, it is a receive buffer allocation,
//otherwise it is a transmit message.
   and   Temp, MsgHdr, 0x3f //get the length
   lsr   MsgHdr, MsgHdr, 10 
   and   MsgHdr, MsgHdr, 0xf //source core
   sub   void, Temp, 1
   jz    sendMACaddress
   sub   void, Temp, 2
   jnz   txMsgRcvd

//message is a buffer allocation
   lsl   Temp, MsgHdr, 1     // 2 * source core
   aqw_add void, Temp, 128   //Rx DMA start address. Negative means drop later frames
   ld    wq, rq
   ld    Temp2, rq           //DMA limit
   sub   void, MsgHdr, 1     //did the message come from core 1?
   jnz   writeLimit          //no.
   ld    void, Temp2
   jm    .+3                 //yes. set or clear mcstOK based on msb(Temp2) 
   andn  Eflags, Eflags, mcstOK  //clear mcstOK
   j     .+2
   or    Eflags, Eflags, mcstOK  //set mcstOK
writeLimit:
   lsl   Temp2, Temp2, 1        //remove msb
   lsr   wq, Temp2, 1
   aqw_add void, Temp, 129  //Rx DMA limit.

//if the source core is one for which a frame is currently arriving, we must set Eflags.newAddr so
//that the DMA address isn't updated when the frame ends.
   and   void, Eflags, arriving
   jz    checkSendReady       //if no frame is arriving, we're done
   lsr   Temp, Index, 1       //the destination core for the incoming frame (in bits 5:1)
   sub   void, Temp, MsgHdr   //did the receive message come from that core?
   jnz   checkSendReady       //no
   or    Eflags, Eflags, newAddr //yes 
   j     checkSendReady

sendMACaddress:
   ld    void, rq             //remove (and drop) one word from rq
   ld    wq, MAChigh
   lsl   Temp, MAClow, 4     //shifts the base address left one nibble
   or    wq, Temp, MsgHdr    //OR in the requesting core number
	
   lsl   Temp, MsgHdr, 3     //the requesting core into bits 3:6 (message destination) 
   or    Temp, Temp, 0x104   //length = 2, I/O device 4 (messenger)
   aqw_add void, IObase, Temp //send the message
	j     checkSendReady
	
txMsgRcvd:
//copy the message payload into DM starting at TxTail + 1. Temp has the length in words
   ld    Addr, TxTail
txCopy:
   aqw_add Addr, Addr, 1
   ld   wq, rq
   sub  Temp, Temp, 1  //decrement the length,
   jnz  txCopy
	
   aqr_ld void, TxTail  //advance TxTail
   ld   Temp, rq
   xor  void, Temp, TxHead   //would advancing TxTail run it into TxHead?
   jz  rejectFrame
   and void, Status, 1       //is the TxLength queue almost full?
   jz  acceptFrame

rejectFrame:
   lsl   MsgHdr, MsgHdr, 3   //Yes; reject Tx request. Originating core into bits 6:3
   or    MsgHdr, MsgHdr, 0x84
   ld    wq, zero           //zero message => reject
   aqw_add void, IObase, MsgHdr
   j     checkSendReady

acceptFrame:   
   ld   TxTail, Temp
   j     checkSendReady

doSend:
  aqr_add void, TxHead, 1    //fetch the payload address
  lsl     Temp, TxHead, 21   //DMbase <- TxHead / 8 in bits 30:24
  ld      wq, rq             //wq <- payload address 
  aqr_add void, TxHead, 2    //fetch the lengths and initiating core (in bits 23:4) bits 3:0 == 1
  or      Temp, rq, Temp     //or in DMbase and send to aq
  aqw_add void, IObase, Temp
  aqr_ld  void, TxHead       //advance TxHead

  ld      wq, Temp           //send a message back to the originating core to indicate the frame was sent. 
  lsr     Temp, Temp, 12     //originating core in bits 6:3
  and     Temp, Temp, 0x78   //mask
  or      Temp, Temp, 0x84   //length = 1, I/O device 4 (messenger)
  aqw_add void, IObase, Temp

  ld      TxHead, rq        
  j       checkFrameArriving


/* The I2C code.  This runs once at initialization.  It reads the Ethernet MAC address (6 bytes)
from an EEPROM.
*/

initMAC:
//This routine writes the MAC address entered by an administrator at macBase into the first 8 locations
//of the EEPROM where they can be read by the controller initialization routine.
   aqr_long_ld  void, macBase
	ld      ma1, zero
initMacLoop:
   ld      md1, rq
	call    initMacWrite
	call    initMacWrite
	call    initMacWrite
	call    initMacWrite
	sub     void, ma1, 8
	jz      return
	aqr_long_ld  void, macBase + datawordsize
	j       initMacLoop
	
initMacWrite:
   ld       wq, link
   aqw_sub  stkp, stkp, datawordsize   // push link
   rol     md1, md1, 8
	call    singleByteWrite  //preserves ma1 and md1
	add     ma1, ma1, 1
	j       return

devSelW = 0xa0;  //device select byte for write
devSelR = 0xa1;  //device select byte for read

scdLL = 0x70       //aqw_add  void, IObase, scdLL causes clock Low, data Low
scdLZ = 0x30
scdZL = 0x50
scdZZ = 0x10

quarterBit = 50  //26    //bit time is 2.5 usec, 1/4 bit is 626 ns, 625/8 is 78 clocks, 78/3 (clocks/delay iteration) is 26.
halfBit    = 100 //52

saveAddress:
    ld       ma1, N
    call     printCh //echo the space
    andn     Flags, Flags, F_Nvalid // clear N valid
    j        chLoop

printByte:
    andn     Flags, Flags, F_odec //print contents in hex
    ld       ma1, N          //the address
    call     printCh         //echo the "p"
	 ld       Char, 0x20
    call     printCh
    call     singleByteRead	 
    ld       N, Char        //byte is returned in Char
    call     printNum
    j        shell

writeByte:
    ld       md1, N          //the data to write. ma1 already has the address
    call     printCh         //echo the "w"
	 call     singleByteWrite
/* If the write succeeded, the EEPROM will be busy for a while, and should not
respond to selection.  i2c setup increments Temp2 each time time selection fails,
so we can attempt to read what we wrote and print out the retry count when
the read completes.
*/
    ld       Char, 0x20        //print space
	 call     printCh
	 ld       Temp2, zero       //clear the retry counter
	 call     singleByteRead
	 ld       N, Char
	 call     printNum         //hopefully, what we wrote
	 ld       Char, 0x20
	 call     printCh
	 ld       N, Temp2        //retry count
	 call     printNum
    j        shell

singleByteRead:
    ld       wq, link
    aqw_sub  stkp, stkp, datawordsize   // push link
    call     i2cSetup //setup for read and write are identical
    call     sendStart                 //reselect the device
    ld       Char, devSelR
    call	    sendByte     
    call     getBit                    //bit into Temp[0]
	 ld       void, Temp
    jnz      noAck
    call     getByte                   //byte into Char                   
    call     getBit                    //get NoACK
	 call     sendStop
    j        return

singleByteWrite:                       //data to write is in md1, address is in ma1
    ld       wq, link
    aqw_sub  stkp, stkp, datawordsize //push link
    call     i2cSetup
	 ld       Char, md1
    call     sendByte
    call     getBit
	 ld       void, Temp
    jnz      noAck
    call     sendStop
    j        return

i2cSetup:
   ld       wq, link
   aqw_sub  stkp, stkp, datawordsize
   call     sendStart
   ld       Char, devSelW
   call     sendByte
   call     getBit
	ld       void, Temp
   jnz      incRetry
   ld       Char, ma1                //the low 8 bits of the address
   call     sendByte
   call     getBit
	ld       void, Temp
   jnz      noAck
   j        return
	
incRetry:
   add      Temp2, Temp2, 1
	j        i2cSetup + 2

sendStart:
// initially, SDA = SCL = Z.  Between bits, SCL = low, SDA Z
   ld       wq, link
   aqw_sub  stkp, stkp, datawordsize
   aqw_add  void, IObase, scdLZ         //SCL low, SDA Z
   ld       count, halfBit
   call     delay
   aqw_add  void, IObase, scdZZ          //SCL Z, SDA Z
   ld       count, quarterBit
   call     delay
   aqw_add  void, IObase, scdZL         //SCL Z, SDA low
   ld       count, quarterBit
   call     delay
   aqw_add   void, IObase, scdLZ         //SCL low, SDA Z
   j        return

sendStop:
  ld       wq, link
  aqw_sub  stkp, stkp, datawordsize
  aqw_add  void, IObase, scdLL          //SCL low, SDA low
  ld       count, halfBit
  call     delay
  aqw_add  void, IObase, scdZL          //SCL Z, SDA low
  ld       count, quarterBit
  call     delay
  aqw_add  void, IObase, scdZZ           //SCL Z, SDA Z
  ld       count, quarterBit
  call     delay
  j        return
  
sendByte:
   ld       wq, link
   aqw_sub  stkp, stkp, datawordsize
   ld       ma2, 128              // mask
   call     sendBit
   ror      ma2, ma2, 1
   jm       return
   j        sendByte + 3

sendBit:
   ld       wq, link
   aqw_sub  stkp, stkp, datawordsize
   ld       count, quarterBit
   call     delay
   and      void, Char, ma2      //test bit
   jz       bitZero
   aqw_add  Temp, IObase, scdLZ    //SCL low, SDA Z (save value in Temp)
   j        bitZero + 1
bitZero:
   aqw_add  Temp, IObase, scdLL    //SCL low, SDA low (save value)
   ld       count, quarterBit
   call     delay
   aqw_andn void, Temp, 0x20        //SCL Z, SDA unchanged
   ld       count, halfBit
   call     delay
   aqw_add  void, IObase, scdLZ   //SCL low, SDA Z
   j        return   

getByte:
   ld       wq, link
	aqw_sub  stkp, stkp, datawordsize
	ld       ma2, 128        //mask
	ld       Char, zero
nextBit:
	call     getBit          //bit into Temp
	ld       void, Temp
	jz       .+2
	or       Char, Char, ma2
	ror      ma2, ma2, 1
	jm       return
	j        nextBit
	
getBit:
   ld       wq, link
	aqw_sub  stkp, stkp, datawordsize
	ld       count, halfBit
	call     delay
	aqw_add  void, IObase, scdZZ  //SCL Z, SDA Z
	ld       count, quarterBit
	call     delay
	aqr_add  void, IObase, scdZZ  //sample SDAin
	ld       Temp, rq
	ld       count, quarterBit
	call     delay
	aqw_add  void, IObase, scdLZ   //SCL low, SDA Z	
	j        return


delay:
   ld       wq, link
   aqw_sub  stkp, stkp, datawordsize
   sub count, count, 1       //delay for (3 * count) + 6 clocks
   jnz  delay + 2
   j    return

noAck:
   call sendStop
	j    start
	
pLoop:
   ld       wq, link
   aqw_sub  stkp, stkp, datawordsize
	call     singleByteRead
	lsl      md1, md1, 8
   or       md1, md1, Char
   add      ma1, ma1, 1
   sub      md2, md2, 1
   jz       return
   j        pLoop + 2	
    



     
        
