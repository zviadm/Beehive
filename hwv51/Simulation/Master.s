 
// © Copyright Microsoft Corporation, 2008, 2009

ARPipAddress =  0xc0a80001 //192.168.0.1 - local TFTPD
	
//register names:
void   = $0
zero   = $0
.assume  zero, 0

t1     = $1
t2     = $2
base   = $2
t3     = $3
linkAddr = $3

a1     = $4
Expected = $4
addr   = $4

ma1    = $5
DataMask = $5
S      = $5
rqCount = $5

ma2    = $6
LastMask = $6;
D      = $6

md1    = $7
PassCount = $7
L      = $7

md2    = $8
Temp2  = $8
DestBase = $8

LowHalf = $9
Base   = $10
K      = $11
Char   = $12
Temp   = $13
Total  = $14
Addr   = $15
Flags  = $16
N      = $17
CoreID = $18
swapMask = $19
EtherCore = $20

Rchksum  = $21
Checksum = $22

result = $23
count  = $24

gotFrame = $25
Received = $25
 
IObase = $26
targetCore = $27
stkp   = $28

F_idec    = 0x01   // input in decimal
F_odec    = 0x02   // output in decimal
F_open    = 0x04   // cell is open
F_Nvalid  = 0x08   // N is valid

// inv=0 cnt=127 line=0 dev=3
FLUSHALL = (0 LSL 19) + (127 LSL 12) + (0 LSL 5) + (3 LSL 2) + 2
 
// inv=1 cnt=127 line=0 dev=3
INVALALL = (1 LSL 19) + (127 LSL 12) + (0 LSL 5) + (3 LSL 2) + 2

// type=1 len=1 dst=1 dev=4
STOPACKMSG = (1 LSL 15) + (1 LSL 9) + (1 LSL 5) + (4 LSL 2) + 2

// type=2 len=0 dev=4. Fill in target dynamically
KILLMSG    = (2 LSL 15) + (4 LSL 2) + 2


// type=1 len=0 dev=4. Fill in target dynamically
STOPMSG    = (1 LSL 15) + (4 LSL 2) + 2

// type=o len=0 dev=4. Fill in target dynamically
STARTMSG    = (0 LSL 15) + (4 LSL 2) + 2


// ------------------------------------------------------------
// Data segment
// ------------------------------------------------------------
    .data
//assemble the stop/start code here so that it is established or
//reestablished whenever the master flushes its data
//cache.

memsize = 0x4000000 //size of main memory = 16MB (must match MBITS in beehive.c)
invalByteAddress = memsize - 0x1000 //used when building the table
invalWordAddress = (invalByteAddress LSR 2) // used to call

  ld       zero, 0 //nop at location 0.
  
 // ld       zero, 0 //four more to compensate for the 10 second delay in Slave.s
 // ld       zero, 0
 // ld       zero, 0
 // ld       zero, 0
  
  ld       wq, $1  //put the registers in WQ
  ld       wq, $2
  ld       wq, $3
  ld       wq, $4
  ld       wq, $5
  ld       wq, $6
  ld       wq, $7
  ld       wq, $8
  ld       wq, $9
  ld       wq, $10
  ld       wq, $11
  ld       wq, $12
  ld       wq, $13
  ld       wq, $14
  ld       wq, $15
  ld       wq, $16
  ld       wq, $17
  ld       wq, $18
  ld       wq, $19
  ld       wq, $20
  ld       wq, $21
  ld       wq, $22
  ld       wq, $23
  ld       wq, $24
  ld       wq, $25
  ld       wq, $26
  ld       wq, $27
  ld       wq, $28
  add      wq, zero, $29  //r29 (via a port) is the read queue.  Use the b port
 
//put savedLink and savedPC into wq
  j7       3        //link <- savedLink
  ld       wq, link
  j7       2        //link <- savedPC
  ld       wq, link

//issue 31 writes to store r1-r29, savedLink, and savedPC to words 1..31 of the save area.
  ld       count, 31
  j7       1        //link <- save area
saveRegs:
  aqw_add  link, link, 4
  sub      count, count, 1
  jnz      .-2

  ld       linkAddr, link  //linkAddr is used for subsequent addressing
//copy rq entries into wq and write them to memory until rq is empty
//count the number of entries with count (now = 0)
rqToWq:
  j7       4    //link <- 0 if rq empty, else 1
  ld       void, link  //test it
  jz       .+5
  ld       wq, rq
  aqw_add  linkAddr, linkAddr, 4
  add      count, count, 1
  j        .-6
  
rqSaved:
  ld       wq, count  //save count in word 0 of the save area
  j7       1   //link <- save area
  aqw_ld   link, link
  
//save is now complete

//build the table of instructions at invalIcache
  long_ld    addr, invalByteAddress
  sub        addr, addr, 32
  ld         count, 127  //first 127 entries (8 words apart) get the jump instruction

buildTable:
  long_ld    wq, 0xf800220c //j .+8
  aqw_add    addr, addr, 32
  sub        count, count, 1
  jnz        .-3
  long_ld    wq, 0xf000030c  //j link
  aqw_add    addr, addr, 32
   
// flush and invalidate the data cache
 
  aqw_long_ld  void,FLUSHALL
  aqw_long_ld  void,INVALALL
 
  // send a message to the master, indicating we've stopped
  //j7      2  // link <- savedPC
  //ld      wq,link      // message payload
  //aqw_long_ld  void,STOPACKMSG
 
// ------------------------------------------------------------
// wait for the master to start us
// ------------------------------------------------------------

waitStart:
  j7     5  //link <- 1 if running, else 0
  ld     void, link   //test it
  jnz    .+2
  j      .-3

restore:
  j7       1 //link <- save area
  sub      link, link, 4  
  ld       count, 32  //issue reads for count, registers 1-29, savedLink, savedPC
readRegs:
  aqr_add  link, link, 4
  sub      count, count, 1
  jnz      .-2
  
reloadRegs:
  ld       $28, rq    //put RQ count into r28
  ld       $1, rq     //load registers 1-27, r29
  ld       $2, rq
  ld       $3, rq
  ld       $4, rq
  ld       $5, rq
  ld       $6, rq
  ld       $7, rq
  ld       $8, rq
  ld       $9, rq
  ld       $10, rq
  ld       $11, rq
  ld       $12, rq
  ld       $13, rq
  ld       $14, rq
  ld       $15, rq
  ld       $16, rq
  ld       $17, rq
  ld       $18, rq
  ld       $19, rq
  ld       $20, rq
  ld       $21, rq
  ld       $21, rq
  ld       $23, rq
  ld       $24, rq
  ld       $25, rq
  ld       $26, rq
  ld       $27, rq
      

//rq now has r28, r29, savedLink, savedPC
//$28 contains the number of RQ entries to restore.
//We use it because r29 isn't a good place to stand
//continue reading until $28 < 0. 
loadRQ:
  sub      $28, $28, 1 //all RQ entries read?
  jm       .+3
  aqr_add  link, link, 4
  j        .-3
  
rqDone:
//rq contains r28, r29, savedLink, savedPC, and the RQ entries.

//invalidate the instruction cache
 long_call invalWordAddress
 
 ld        $28, rq    //load r28
 ld        $29, rq    //load r29
 ld        link, rq   //load link
 j         rq         //transfer to user code.


//----------------------------------------------
//The test program for the debug unit
//----------------------------------------------
.word 0
.word 0
testDebug:
  ld    $1, 1
  ld    $2, 2
  j7    6     //breakpoint
  ld    $1, 3
  ld    $2, 4
  j7    6    //another
  aqr_ld void, 0
  aqr_ld void, 4
  j7    6   //break with 2 entries in rq
  ld    void, rq
  ld    void, rq
loopForever:
  ld    $1, 5
  ld    $2, 6
  j     .-2

//----------------------------------------------------
//The packet headers and payload locations used by the 
//tiny TFTP
//----------------------------------------------------
decwords = 10
hexwords = 8
dectable: .blkw decwords
hextable: .blkw hexwords

    .blkw 16
stack:

myMACaddress: .word 0  //network byte order
  .word 0
myIPaddress: .word 0  //machine byte order

//The following is a 13-word table with the values for DHCP options 1-3 and 50-59
//from a DHCP OFFER or ACK packet.
optSubnetMask:  .word 0 //option 1
optTimeOffset:  .word 0
optRouter:      .word 0
optRQIPaddress: .word 0 //option 50
optIPleaseTime: .word 0
optOverload:    .word 0
optMsgType:     .word 0 //DHCP message type (1 byte)
optServerID:    .word 0
optParamRq:     .word 0 //parameter request list (client shouldn't see this)
optMessage:     .word 0
optMaxDHCPsize: .word 0
optRenewTime:   .word 0
optRebindTime: .word 0
optTableWords = ((. - optSubnetMask) / datawordsize) 

 
 
.align 32                                      
UDPpayload:              //cache line aligned
  .blkw 48               //192 bytes of zero
  .word 0x63538263       //little-endian magic cookie
opt0: .word 0            //DHCP options filled in dynamically
opt1: .word 0
opt2: .word 0
opt3: .word 0
UDPpayloadLength = (. - UDPpayload)  //payload length (bytes)

//The DHCP discover packet header to send to the Ethernet controller in a message
DISCOVERmsg:
.word     (UDPpayload - data) / 32 //payload address (a cache line address).
.word     (dEheaderLength LSL 19) + (UDPpayloadLength LSL 4) + 1  //total header length (words) + packet length (bytes).
//**Must fill in whichCore dynamically
//----Ethernet Header
.word     0xffffffff           //ethernet broadcast MAC address high
.word     0xffff0800           //address low, Ethertype
//----IP header
.word     (4 LSL 28) + (5 LSL 24) + dIPdatagramLength  //IPV4, header length(5 words), datagram length (bytes)
.word     0x0                  //Identification, flags, fragment offset
.word     (0x8011 LSL 16)      //TTL, protocol (UDP).  **Must fill in header checksum dynamically
.word     0x0                  //source IP address
.word     0xffffffff           //destination IP address (broadcast)
//----UDP header
.word     (68 LSL 16) + 67     //source and destination ports (DHCP)
.word     (dUDPdatagramLength LSL 16) //datagram length (bytes), checksum (0)
//----DHCP header
.word     0x01010600           //op, htype, hlen, hops
.word     0xfeedface           //xid
.word     0x0                  //secs, flags
.word     0x0                  //ciaddr
.word     0x0                  //yiaddr
.word     0x0                  //siaddr
.word     0x0                  //giaddr
.word     0x0                  //chaddr: msb of 48 bit MAC address.
.word     0x0                  //chaddr: lsb of 48 bit MAC address in MSB.
.word     0x0
.word     0x0

dEheaderLength =     ((. - DISCOVERmsg) - (2 * datawordsize)) / datawordsize
dIPdatagramLength =  ((. - DISCOVERmsg) - (4 * datawordsize)) + UDPpayloadLength
dUDPdatagramLength = ((. - DISCOVERmsg) - (9 * datawordsize)) + UDPpayloadLength
dUDPmessageLength =   (. - DISCOVERmsg) / datawordsize


.align 32
TFTPpayload:  //for the TFTP request message. Filename "capture", mode "octet"
.word 0   //first two chars of name, opcode
.word 0   //'o', 0x0, last two chars of name
.word     0x74657463  //'t','e','t','c'
.word 0   

TFTPpayloadLength = (. - TFTPpayload)

//The TFTP request packet header to send to the Ethernet controller in a request message
TFTPmessage:
.word     (TFTPpayload - data) / 32 //payload address (a cache line address).
.word     (tEheaderLength LSL 19) + ((TFTPpayloadLength - 3) LSL 4) + 1  //total header length (words) + packet length (bytes).
//**Must fill in whichCore dynamically
//----Ethernet Header
.word     0           //destination MAC address high
.word     0           //destination MAC address low, Ethertype (0800)
//----IP header
.word     (4 LSL 28) + (5 LSL 24) + tIPdatagramLength  //IPV4, header length(5 words), datagram length (bytes)
.word     0x0                  //Identification, flags, fragment offset
.word     (0x8011 LSL 16)      //TTL, protocol (UDP).  **Must fill in header checksum dynamically
.word     0                    //source IP address (me)
.word     0                    //destination IP address (TFTP server)
//----UDP header
.word     0     //Destination and source ports filled in dynamically
.word     (tUDPdatagramLength LSL 16) //datagram length (bytes), checksum (0)

tEheaderLength =     ((. - TFTPmessage) - (2 * datawordsize)) / datawordsize
tIPdatagramLength =  ((. - TFTPmessage) - (4 * datawordsize)) + TFTPpayloadLength - 3
tUDPdatagramLength = ((. - TFTPmessage) - (9 * datawordsize)) + TFTPpayloadLength - 3
tUDPmessageLength =   (. - TFTPmessage) / datawordsize

.align 32
ARPpayload:        //cache line aligned 
.word 0x00080100   //protocol type, hardware type
.word 0x01000406   //operation, protocol length, hardware length
arpSHA: .word 0    //sender hardware address (first 32 bits)
arpSPA: .word 0    //sender hardware address (low 16 bits), sender protocol address (first 16 bits)
arpSPA1: .word 0   //sender prootocol address (last 16 bits), target hardware address (first 16 bits)
arpTHA: .word 0    //target hardware address
arpTPH: .word 0    //target protocol address
.word 0            //padding
.word 0
.word 0
.word 0
ARPpayloadLength = (. - ARPpayload)  //length in bytes

ARPmessage: 
.word  (ARPpayload - data) / 32  //payload cache line address
.word  (2 LSL 19) + (ARPpayloadLength LSL 4) + 1
//----Ethernet Header
.word     0xffffffff           //ethernet broadcast MAC address high
.word     0xffff0806           //address low, ARP    
ARPmessageLength = (. - ARPmessage)


 


.align 32
TFTPpayload1:
.word    0            //this is the ACK payload (1 word) of block number (16 bits) and ACK (opcode = 4)
//The TFTP ack packet header to send to the Ethernet controller in an ack message

TFTPAckMessage:
.word     (TFTPpayload1 - data) / 32 //payload address (a cache line address).
.word     (t1EheaderLength LSL 19) + (4 LSL 4) + 1  //total header length (words) + packet length (bytes).
//**Must fill in whichCore dynamically
//----Ethernet Header
.word     0           //destination MAC address high
.word     0           //destination MAC address low, Ethertype (0800)
//----IP header
.word     (4 LSL 28) + (5 LSL 24) + t1IPdatagramLength  //IPV4, header length(5 words), datagram length (bytes)
.word     0x0                  //Identification, flags, fragment offset
.word     (0x8011 LSL 16)      //TTL, protocol (UDP).  **Must fill in header checksum dynamically
.word     0                    //source IP address (me)
.word     0                    //destination IP address (TFTP server)
//----UDP header
.word      0                   //both ports filled in dynamically
.word     (t1UDPdatagramLength  LSL 16)           //total length

t1EheaderLength =     ((. - TFTPAckMessage) - (2 * datawordsize)) / datawordsize
t1IPdatagramLength =  ((. - TFTPAckMessage) - (4 * datawordsize)) + 4 /// (ack payload is 4 bytes long)
t1UDPdatagramLength = ((. - TFTPAckMessage) - (9 * datawordsize)) + 4
t1UDPmessageLength =   (. - TFTPAckMessage) / datawordsize


bufferMsg:
  .word  ((packetBuffer - data) / 32)        //DMA cache line address
  .word  2 //DMA cache line limit.  Small so that packets will be discarded without a new allocation.

rcvBuffer:
  .blkw  4    //The receive complete message payload goes here.

.align 4096   //DMA can't write into the Dcache, so put the packet beyond it 
packetBuffer: blkw 1024  //place to put received data

packetBufferWords = ((. -packetBuffer)/ datawordsize)


// ------------------------------------------------------------
// Memory mapped IO definitions
// ------------------------------------------------------------
    .abs    0x80000000 ROL datawordror
IO_:
IO_ASLI:   .blkw 1    //local I/O device 0
IO_MULT:   .blkw 1    //local I/O device 1
IO_OUTREG: .blkw 1    //local I/O device 2
           .blkw 1    //local I/O device 3
IO_MSGR:   .blkw 1    //local I/O device 4

// ------------------------------------------------------------
// Code segment
// ------------------------------------------------------------
    .code
    .word    0
start:
//    andn     zero, zero, zero       // initialize zero
//    .assume  zero, 0                // henceforth assume it
 
    long_ld  IObase, IO_            // initialize IObase
    .assume  IObase, IO_            // henceforth assume it

    long_ld  LowHalf, 0xffff
    
    long_ld  stkp, stack            // initialize stkp
	 ld       targetCore, 2          // initialize targetcore

//cjt: store end of memory address in 0xffc
    long_ld addr,0xffc
    aqw_ld  void,addr
    long_ld wq,invalByteAddress

//read locations 0 - 0xffc and write them to themselves,
//thereby making the data cache dirty.
    sub   addr, zero, 32
    ld    count, 128
dirtyLoop:
    aqr_add  addr, addr, 32
    ld      wq, rq
    aqw_ld  void, addr
    sub     count, count, 1
    jnz     dirtyLoop

    // ensure Master D cache flush before slave starts	
    aqw_long_ld  void,FLUSHALL
	
// ----------------------------------------
// build a table of powers of 10
// ----------------------------------------
    long_ld	  Base, dectable-datawordsize
    ld       N, decwords
    ld       t3, 1
decloop:
    ld       wq, t3
    aqw_add  Base, Base, datawordsize
    lsl      t1, t3, 1            // X2
    lsl      t3, t3, 3            // X8
    add      t3, t3, t1           // X10 = X8 + X2
    sub      N, N, 1
    jnz      decloop
	
// ----------------------------------------
// build a table of powers of 16
// ----------------------------------------
    long_ld  Base, hextable-datawordsize
    ld       N, hexwords
    ld       t3, 1
hexloop:
    ld       wq, t3
    aqw_add  Base, Base, datawordsize
    lsl      t3, t3, 4            // X16
    sub      N, N, 1
    jnz      hexloop

// ------------------------------------------------------------
// Simulation Code
// ------------------------------------------------------------
    
  call     0x1000

// ------------------------------------------------------------
// Shell initialization.
// ------------------------------------------------------------
shell:
    ld       N, 0
    ld       Flags, F_idec|F_odec
    aqr_ld   void, IO_ASLI
    ld       Temp, rq
    lsr      CoreID, Temp, 10
    and      CoreID, CoreID, 0xf
    lsr      EtherCore, Temp, 14
    and      EtherCore, EtherCore, 0xf	 


//    j       memTest

shellPrompt:
    call     printCRLF
    ld       N, CoreID
    call     printNum
	 ld       Char, " "
	 call     printCh
	 ld       N, targetCore
	 call     printNum
    ld       Char, ">"
    call     printCh
	 andn     Flags, Flags, F_Nvalid  //N is not valid at the prompt
	 ld       N, zero
    
    
// ------------------------------------------------------------
// Read and process command character.
// ------------------------------------------------------------
chLoop:
    aqr_ld   void, IO_ASLI           
    ld       Char, rq               // Read RS232
    and      void, Char, 0x100      // Test for receiver full
    jnz      doChar
    aqr_ld   void, IO_MSGR          //any messages?
    ld       Char, rq
    jz       chLoop
//we need the message length and the source core
gotMessage:
    lsr      md1, Char, 10 
    and      md1, md1, 0x3f        //source core
    and      md2, Char, 0x3f       //length
    ld       ma1, rq               //first word of the payload
    and      Char, Char, 0x3f
drainLoop:
    sub      Char, Char, 1
    jz       printStop
    ld       void, rq              //since it's a disaster to leave extras on RQ, drain any.
    j        drainLoop

printStop:
    andn     Flags, Flags, F_odec  //print in hex
    call     printCRLF
    ld       N, md1
    call     printNum
    ld       Char, "s"
    call     printCh
    ld       Char, " "
    call     printCh
    ld       N, md2
    call     printNum
	 ld       Char, " "
	 call     printCh
    ld       N, ma1
    call     printNum
	 aqr_ld   void, IO_MSGR  //any more messages?
    ld       Char, rq
    jnz      gotMessage
    j        shellPrompt
	 

doChar:
    ld       wq, 0x100              // Reenable the receiver
    aqw_ld   void, IO_ASLI

    and      Char, Char, 0x7f       // Mask to 7 bits
    sub      void, Char, "/";   jz openCellHexOut
    sub      void, Char, "\\";  jz openCellDecOut
    sub      void, Char, ">";   jz nextCell
    sub      void, Char, "<";   jz prevCell
    sub      void, Char, 13;    jz closeCell
    sub      void, Char, "x";   jz hexData
    sub      void, Char, "X";   jz decData
    sub      void, Char, "g";   jz go
    sub      void, Char, "r";	  jz release
    sub      void, Char, "s";   jz sendStop
    sub      void, Char, "k";   jz sendKill
    sub      void, Char, "j";   jz jumpTo
    sub      void, Char, "t";   jz setTarget
    sub      void, Char, "|";   jz openTargetReg
    sub      void, Char, "z";   jz getFile  //run the DHCP/TFTP "BIOS".
    sub      void, Char, "*";   jz mulArg1  //first argument of multiply is in N
    sub      void, Char, "=";   jz mulArg2  //second argument of multiply is in N, start multiply, print result

    sub      void, Char, "0";   jm chLoop   // Char must be >= "0"...
    sub      void, Char, "9"+1; jm digitDec // have digit 0-9
    
    sub      void, Char, "a";   jm chLoop   // must be >= "a"...
    sub      void, Char, "f"+1; jm digitHex // have digit a-f
    j        chLoop

jumpTo:
    ld      Temp, 0x20
    add_lsl Temp, Temp, targetCore, 9
//	 lsl      Temp, targetCore, 10
//if N is valid, it is the starting location.
//Otherwise, we add one to the savedPC to set
//the restart PC.
    and       void, Flags, F_Nvalid
	 jnz       restartCore
    aqr_add   void, Temp, 124
	 add       N, rq, 1
restartCore:	 
	 aqw_add  void, Temp, 124  //savedPC's offset is 31 words.
	 ld       wq, N
//flush and invalidate the data cache
    aqw_long_ld  void,FLUSHALL
    aqw_long_ld  void,INVALALL
//send a start message to the target
    ld       ma1, STARTMSG
	 j        sendMsg

sendKill:
    long_ld  ma1, KILLMSG
    j        sendMsg
	 
sendStop:
    long_ld  ma1, STOPMSG
sendMsg:
    call     printCh    //echo the command character
	 lsl      Temp, targetCore, 5
	 aqw_add  void, Temp, ma1  //send the start or stop message to the target
	 j        shellPrompt
	 
setTarget:
    call     printCh  //echo
    and      void, Flags, F_Nvalid
    jz       shellPrompt  //don't change unless N is valid
    ld       targetCore, N
    j        shellPrompt
	 
openTargetReg:
     ld       Temp, 0x20
     add_lsl  Temp, Temp, targetCore, 7
//   lsl      Temp, targetCore, 8
	add_lsl  N, N, Temp, 2      //n is a register number.  We need a byte address
	or       Flags, Flags, F_Nvalid  //make N valid
	j        openCellHexOut

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
    ld       Addr, N                // N is a byte address.
    
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
    and      void, Flags, F_Nvalid  // is N valid?
    jnz      chLoop                 // yes, cannot change input radix...
    andn     Flags, Flags, F_idec
    call     printCh
    j        chLoop


decData:
    and      void, Flags, F_Nvalid  // is N valid?
    jnz      chLoop                 // yes, cannot change input radix...
    or       Flags, Flags, F_idec
    call     printCh
    j        chLoop

nextCell:
    ld       t3, datawordsize       // t3 = delta
    j        changeCell

prevCell:
    ld       t3, -datawordsize      // t3 = delta

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
    jz       closeCell.done
    and      void, Flags, F_Nvalid  // is N valid?
    jz       closeCell.done         // nothing entered...
    ld       wq, N
    aqw_ld   void, Addr             // store value at address

closeCell.done:
    andn     Flags, Flags, F_open|F_Nvalid    // clear cell open, N valid
    j        shellPrompt    

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
    long_ld  Base, hextable+(hexwords*datawordsize)
    and      void, Flags, F_odec    // test for hex out mode
    jz       printNum.digitloop     // yes...
    ld       K, decwords
    long_ld  Base, dectable+(decwords*datawordsize)
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
    // Not willing to trust the CARRY bit, we
    // compute the bit wise carryout via bit hacking.
    // ----------------------------------------
    sub      t1, N, t3          // t1 = (N + ~t3 + 1)
    xor      t1, t1, N
    xorn     t1, t1, t3         // t1 = bit wise carryin
    orn      t2, N, t3
    and      t2, t2, t1         // t2 = bit wise carryin & (N | ~t3)
    andn     t1, N, t3          // N & ~t3
    or       t1, t1, t2         // t1 = bit wise carryout
    jnm      printNum.trialdone // nope, N < t3...
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
/*
   aqr_ld    void, IO_MSGR
   and       void, rq, 0x3f         //should be zero (message queue should be empty
   jz        .+4
   ld        Char, "X"              //print to indicate error
   call      printCh
   j         start	
*/
//flush and invalidate the data cache
   aqw_long_ld  void,FLUSHALL
   aqw_long_ld  void,INVALALL
   call     N                      // go
   j        start
	 
getFile:
    call    DHCPclient
	 j       start

release:                            //release the RS232
    aqw_ld   void, IO_OUTREG
    ld       wq, 1
    aqw_ld   void, IO_OUTREG
    ld       wq, zero
    j        start

mulArg1:
    ld       ma1, N
    call     printCh //echo the "*"
    andn     Flags, Flags, F_Nvalid // clear N valid
    j        chLoop

mulArg2:
    ld       ma2, N
    call     printCh         //echo the "="
    ld       wq, ma1
    ld       wq, ma2
    aqw_ld   void, IO_MULT  //start the multiply
    ld       N, rq
    ld       ma1, rq
    call     printNum
    ld       Char, ","
    call     printCh
    ld       N, ma1
    call     printNum
    j        shell

/*
//Read cycle counter
readCycleCount:
    call     printCRLF
    aqr_ld   void, 0x22  //I/O space, device 0, aq[3] = 1
	 ld       N, rq
	 call     printNum
	 j        start 


// ------------------------------------------------------------
//Memory test
// ------------------------------------------------------------

memTest:
    sub    void, CoreID, 1
    jz     doCore1
//This is not core 1. Run the test
    aqw_ld   void, IO_OUTREG //release the RS232
    ld       wq, 1
    aqw_ld   void, IO_OUTREG
    ld       wq, zero

    long_ld LastMask, 0x7ffffff
    ld DataMask, zero
    ld PassCount, zero
    aqr_ld   void, 0x22  //cycle counter: I/O space, device 0, aq[3] = 1
    ld       count, rq

restart:
    lsl     Addr, CoreID, 27
wrLoop:
    aqw_add Addr, Addr, datawordsize
    xor     wq, Addr, DataMask
    and     void, Addr, LastMask
    jnz     wrLoop
    lsl     Addr, CoreID, 27
rdLoop:
    aqr_add Addr, Addr, datawordsize
    xor     Temp, Addr, DataMask  //expected value
    and     void, Addr, LastMask
    jz      passDone
    xor     Temp2, rq, Temp
    jz      rdLoop
rdError:
    xor     Temp2, Temp2, Temp  //recover what we read
    ld      wq, zero            //send a one-word zero message to core 1
    aqw_ld  void, 0x232         //core 1, length 1, device 4 (messenger)
    j       .                   //halt

passDone:
    ld      void, rq   //read the last word
    add     PassCount, PassCount, 1
    ld      void, DataMask
    sub     Temp, zero, 1
    xor     DataMask, DataMask, Temp //complement DataMask
    ld      Temp, count
    aqr_ld  void, 0x22  //cycle counter: I/O space, device 0, aq[3] = 1
    ld      count, rq
    sub     wq, count, Temp  //pass length in cycles. Send in a 1-word message to core 1.
    aqw_ld  void, 0x232      //core 1, length 1, device 4 (messenger)
    j       restart

doCore1:
   aqr_ld    void, IO_MSGR   //drain the message queue
   ld        Temp, rq
   and       Temp, Temp, 0x3f  //mask length
   jz        .+5
   ld        void, rq
   sub       Temp, Temp, 1
   jz        doCore1
   j         .-3

waitMsgs:
   aqr_ld    void, IO_MSGR
   ld        Temp, rq
   lsr       Addr, Temp, 10 
   and       Addr, Addr, 0xf        //source core (we don't use the type)
   and       Temp, Temp, 0x3f       //mask length
   jz        waitMsgs
   ld        Temp2, rq              //the message word
   sub       void, Temp, 1
   jnz       .-1                    //incorrect length
   call      printCRLF
   ld        N, Addr
   call      printNum
   ld        Char, ":"
   call      printCh
   ld        Char, " "
   call      printCh
   ld        N, Temp2
   call      printNum
   j         waitMsgs
 */
 
 
 
// ------------------------------------------------------------
//Zero count words starting at a1
// ------------------------------------------------------------
initMem:
   ld       wq, link
   aqw_sub  stkp, stkp, datawordsize
   sub      a1, a1, datawordsize
memLoop:
   ld       wq, zero
   aqw_add  a1, a1, datawordsize
   sub      count, count, 1
   jnz      memLoop
   j        ret
	
// ------------------------------------------------------------
//Send a message;
//  t1 has destination core number
//  t2 has message length (> 0) in words
//  t3 has the message payload (byte) address
// ------------------------------------------------------------
sendMessage:
   ld       wq, link          //push link
   aqw_sub  stkp, stkp, datawordsize
   ld       count, t2
   sub      Addr, t3, datawordsize
smLoop:
   aqr_add  Addr, Addr, datawordsize
   ld       wq, rq
   sub      count, count, 1
   jnz      smLoop
   lsl      Temp, t2, 9      //length
   lsl      t1, t1, 5        //dest core
   add      Temp, Temp, t1
   aqw_add  void, Temp, 0x12 //IO device 4 (messenger)
   j        ret

// ------------------------------------------------------------
//Receive a message;
//  count has the number of rmLoop iterations to wait before returning
//  Returns the length (6 bits) in result, or zero if timeout.
//  Returns the source core in t1
//  On a nonzero return, caller must extract length words from rq.
//  Doesn't use the stack, since the rq would be accessed by the return sequence
// ------------------------------------------------------------
receiveMessage:
   ld        t3, link
rmLoop:
   aqr_ld    void, IO_MSGR
   ld        result, rq
   lsr       t1, result, 10 
   and       t1, t1, 0xf            //source core (we don't use the type)
   and       result, result, 0x3f   //mask length
   jnz       t3
   sub       count, count, 1
   jz        t3
   j         rmLoop

  
// ------------------------------------------------------------
//Generate an IP checksum.
//  ma1 has the starting address of the range of words to be checksummed.
//  count contains the number of words to be checksummed.
//  returns with the checksum in result.
// ------------------------------------------------------------

checksum:
     ld        wq, link
     aqw_sub   stkp, stkp, datawordsize
     ld        result, zero
     sub       ma1, ma1, datawordsize
sumLoop:
     aqr_add   ma1, ma1, datawordsize
     ld        Temp, rq
     lsr       ma2, Temp, 16       //high half into low half of ma1
     and       Temp, Temp, LowHalf //mask out high half
     add       result, result, Temp //add low half
	  add       result, result, ma2  //add high half
     sub       count, count, 1
     jnz       sumLoop
     lsr       Temp, result, 16         //get carries
     add       result, result, Temp     //add them in
     and       result, result, LowHalf  //get low 16 bits
     xor       result, result, LowHalf  //complement
     j         ret


// ------------------------------------------------------------
//Patch the CoreID into the dynamic fields of an IP
//message, and generate the packet IP header checksum
//Addr contains the address of the message
// ------------------------------------------------------------

patchHeader:  //patch the Ethernet header, generate the IP checksum
    ld         wq, link
    aqw_sub    stkp, stkp, datawordsize
    aqr_add    void, Addr, (1 * datawordsize)
    ld         t1, rq
	 
	 ld         t2, 0xf   //clear the field
	 lsl        t2, t2, 15
	 andn       t1, t1, t2
	 
    lsl        t2, CoreID, 15
    or         wq, t1, t2
    aqw_add    void, Addr, (1 * datawordsize)

    aqr_add    void, Addr, (6 * datawordsize)
    andn       t1, rq, LowHalf //clear the header checksum
	 ld         wq, t1          //keep high half in t1 for subsequent OR
    aqw_add    void, Addr, (6 * datawordsize)
    add        ma1,  Addr, (4 * datawordsize) //start the checksum 4 words into the message
    ld         count, 5                       //checksum 5 words
    call       checksum
    or         wq, t1, result  //or checksum and original high half
    aqw_add    void, Addr, (6 * datawordsize)
	 j          ret
 
	


// ------------------------------------------------------------
//Send a message and wait for a reply
//md1 has the message length
//md2 is the address of the message
// ------------------------------------------------------------ 
sendRcv:
    ld         wq, link
    aqw_sub    stkp, stkp, datawordsize
	 
    ld         count, packetBufferWords
    ld         a1, (packetBuffer - data)	 
    call       initMem    //zero the receive buffer
	 
    ld         count, optTableWords //option table length
    ld         a1, (optSubnetMask - data)
    call       initMem             //clear the option table
	 
    aqw_long_ld    void, 0x7f00e //flush

//send a message to the Ethernet controller with a receive buffer allocation
    ld         t1, EtherCore       //sending to the Ethernet controller.
    ld         t2, 2       //buffer message length
    ld         t3, (bufferMsg - data)
    call       sendMessage

//send a message to the Eternet controller to cause it to send the packet
    ld         t1, EtherCore
    ld         t2, md1
    ld         t3, md2
    call       sendMessage

    aqw_long_ld    void, 0xff00e //invalidate the cache
	 
//wait for a message
waitMsg:
    long_ld    count, 20000000    //Timeout. ~10 cycles/iteration.
    call       receiveMessage
    ld         Temp, result
    jnz        checkLength       //Should be 1 or 3, not zero.
    sub        wq, zero, 1       //No reply within timeout. Store -1 in rcvBuffer
    aqw_ld     void, (rcvBuffer - data)
    j          ret
checkLength:
    sub        void, result, 1  //transmit complete message?
    jnz        getMessage
    ld         void, rq         //read the 1-word transmit complete payload from rq
    j          waitMsg          //wait for a more interesting message
	 
getMessage:

/* We're only interested in receive complete  messages from the controller.
The message is 4 words:
  the frame length in bytes
  the source MAC address
  the destination MAC address
  the cache line address used to store the frame
We're not interested in these things (because DHCP clients use broadcast), but
we check for a transmit complete message (4 words long), and store the contents
of the message in rcvBuffer.  Any other length is stored in rcvBuffer + 4, -2 is
stored in rcvBuffer, and we return to the caller.
*/
    sub       void, result, 4
    jz        storeMessage          //Correct length?
	 
emptyRQ:
    ld         t1, result    //save length
    ld         void, rq      //Drain the message from rq.
    sub        result, result, 1
    jnz        emptyRQ + 1
    ld         wq, t1
    aqw_ld     void, (rcvBuffer - data) + datawordsize //store length in rcvBuffer + 1
    sub        wq, zero, 2  //store - 2 in rcvBuffer
    aqw_ld     void, (rcvBuffer - data)
    j          ret
 
storeMessage:	 
    ld         a1, ((rcvBuffer - data) - datawordsize)
getNextWord:
    aqw_add    a1, a1, datawordsize
    ld         wq, rq
    sub        result, result, 1
    jnz        getNextWord

    j ret
    // If we transmitted an IP packet, check that the received packet
    // it is from the TFPT server (ARPipAddress).
    aqr_add		void, md2, (3 * datawordsize)
    ld		Temp, rq
    lsl		Temp, Temp, 16
    lsr		Temp, Temp, 16

    ld		Temp2, 0x0800
    sub		void, Temp, Temp2
	
    jnz		ret
    // We trasnmitted an IP packet

    long_ld   	t1, (packetBuffer - data) + (3 * datawordsize)
    aqr_ld	void, t1
    ld		Temp, rq
    call	byteSwap
	
    long_ld	Temp2, ARPipAddress

    sub		void, Temp, Temp2

    jnz		waitAgain
	
    j          	ret

waitAgain:
    ld         Char, "-"
    call       printCh

    ld         count, packetBufferWords
    ld         a1, (packetBuffer - data)	 
    call       initMem    //zero the receive buffer
	 
    aqw_long_ld    void, 0x7f00e //flush

    //send a message to the Ethernet controller with a receive buffer allocation
    ld         t1, EtherCore       //sending to the Ethernet controller.
    ld         t2, 2       //buffer message length
    ld         t3, (bufferMsg - data)
    call       sendMessage

    aqw_long_ld    void, 0xff00e //invalidate the cache

    j	waitMsg


// ------------------------------------------------------------
//Get the next byte from a word array.
//Addr initially points to the word preceding the first word of the array.
//t1's low order two bits have the byte index.  When they are 00,
//the next word of the array is fetched
// ------------------------------------------------------------
getNextByte:

//leaf routine, so don't use stack
    ld         t3, link
    and        void, t1, 0x3
	 jnz        . + 3           //if index is 0 mod 4, fetch another word
	 aqr_add    Addr, Addr, datawordsize
	 ld         t2, rq
	 and        Temp, t2, 0xff  //extract the low byte of t2
	 lsr        t2, t2, 8       //shift right in preparation for the next access
	 add        t1, t1, 1       //increment byte index.
	 j          t3
	 
	 
/* checkOffer examines the received packet.  If it appears correct, it fills in optTable
with the DHCP options (little endian), and leaves the length in the rcvBuffer unchanges (positive).
If the "magic cookie" is incorrect, it stores - 3 into rcvBuffer and returns.
*/  
checkOffer:
    ld         wq, link
    aqw_sub    stkp, stkp, datawordsize
    long_ld    Addr, (packetBuffer - data) + 0x108
	 aqr_ld     void, Addr
	 long_ld    t1, 0x63538263       //little-endian magic cookie 
	 xor        void, rq, t1
    jz         parseOptions
    sub        wq, zero, 3         //bad cookie.  Store -3 in rcvBuffer
	 aqw_ld     void, (rcvBuffer - data)
    j          ret

parseOptions:
    ld         t1, zero            //t1 contains the byte offset in the packet.
nextOption:
    call       getNextByte         //returns the next option byte in Temp
    ld         result, Temp        //put the option in result
	 jz         nextOption          //it's padding
	 xor        void, result, 0xff
	 jz         ret              // 0xff is end of options
    call       getNextByte         //Temp := option length in bytes
	 ld         md1, Temp           //save length in md1
    ld         md2, zero           //accumulate the option in md2
	 
getOptionValue:
//note that options with length > 4 are not handled properly.
    call       getNextByte
    lsl        md2, md2, 8
    or         md2, md2, Temp
    sub        md1, md1, 1
    jnz        getOptionValue
	  
//We have the option.  Figure out where to put it in the value table.
    sub        void, result, 4  //result - 4 < 0 => result < 4
	 jnm        .+5
	 ld         wq, md2          //option value
	 lsl        result, result, 2 //offset in table in bytes
	 aqw_add    void, result, (optSubnetMask - data) - datawordsize //option 1 goes at offset 0
	 j          nextOption
	 sub        void, result, 50 //result - 50 < 0 => result < 50
	 jm         nextOption       //ignore options 4-49
	 sub        void, result, 60 //result - 60 < 0 => result < 60
	 jnm        nextOption       //ignore options > 59
	 ld         wq, md2          //option value
	 sub_lsl    result, result, 50, 2  //subtract 50, shift left 2
	 aqw_add    void, result, (optRQIPaddress - data) //option 50 goes at offset 0
    j          nextOption

// ------------------------------------------------------------
//swap the bytes of Temp
// ------------------------------------------------------------
byteSwap: 
   ror        t2, Temp, 8      //bytes 1 and 3 correctly located
   and        t2, t2, swapMask //mask them
   ror        Temp, Temp, 24    //bytes 0 and 2 correctly located (left 8 = ror 24
   andn       Temp, Temp, swapMask  //mask them
   or         Temp, Temp, t2
   j          link


// ------------------------------------------------------------
//Send an ARP request for the IP address in Addr.
//Returns when the ARP reply is received (or times out).
//If all is well (rcvBuffer >= 0), the ARP reply packet is in the
//packetBuffer.
//The ARP packet uses the base MAC address, but this is OK since
//it's a broadcast protocol, and the real MAC address is in the
//message.
// ------------------------------------------------------------
	 
sendARP:
    ld         wq, link
    aqw_sub    stkp, stkp, datawordsize
    aqr_ld     void, (myMACaddress - data)  //fill in the ARP packet fields
    aqr_ld     void, (myMACaddress - data) + datawordsize
    aqw_ld     void, (arpSHA - data)
    ld         Temp, rq
    call       byteSwap   //MAC address is in network byte order, we need machine order 
    ld         wq, Temp   //store arpSHA
	 
    ld         Temp, rq   //low 16 bits of SHA in high half
    call       byteSwap
    and        t1, Temp, LowHalf
	 
    aqr_ld     void, (myIPaddress - data)
    ld         Temp, rq      //in machine byte order
    lsl        t2, Temp, 16  //high bits of IP address into bits 31:16
    or         wq, t1, t2
    aqw_ld     void, (arpSPA - data)
	 
    lsr        wq, Temp, 16  //low bits of IP address into bits 15:0
    aqw_ld     void, (arpSPA1 - data)
	 
    ld         Temp, Addr   //the IP address whose MAC address we need, in network byte order
    call       byteSwap
    ld         wq, Temp
    aqw_ld     void, (arpTPH - data)

    ld         md1, ARPmessageLength
    ld         md2, (ARPmessage - data)

    aqr_add    void, md2, datawordsize  //patch coreID into the second word of the ARPmessage
    ror        Temp, rq, 15
    andn       Temp, Temp, 0xf
    or_ror     wq, Temp, CoreID, 17  //left 15 = ror 17
    aqw_add    void, md2, datawordsize
 	 
    call sendRcv
    j          ret	 
	
// ------------------------------------------------------------
//A simple DHCP client.
// ------------------------------------------------------------

DHCPclient:
    ld         wq, link
    aqw_sub    stkp, stkp, datawordsize
	 long_ld    swapMask, 0xff00ff00
	 
//empty the message queue
emptyMQ:
   aqr_ld    void, IO_MSGR
   ld        result, rq
   and       result, result, 0x3f  //mask length
	jz        .+5
	ld        void, rq
	sub       result, result, 1
	jz        emptyMQ
   j         .-3
	
//get this core's MAC address from the Ethernet controller
   ld        wq, zero    //One word message payload (ignored by the Ethernet controller)
	lsl       Temp, EtherCore, 5
	or        Temp, Temp, 512
	aqw_or    void, Temp, 0x12  //write I/O device 4 to send the message
	long_ld   count, 10000
	call      receiveMessage
//If the length is 2 and the source core is EtherCore, copy the
//two words from rq into memory
   sub       void, result, 2
   jnz       failMAC              //length != 2
	sub       void, t1, EtherCore
	jnz       failMAC              //message came from the wrong core
	ld        wq, rq               //move 2 words from rq to wq
	lsl       Temp, rq, 16         //MAC lsb goes in high halfword
	ld        wq, Temp
	aqw_ld    void, (myMACaddress - data)
	aqw_ld    void, (myMACaddress - data) + datawordsize
	
//use the 4 nibbles of the MAC address low as the filename to request
//from the TFTP server.
   ld        t2, 0x100           //read request
   call      extractChar         //t1 <- first char of name
   lsl       t1, t1, 16
   call      extractChar1        //t1 <- second char of name
   lsl       t1, t1, 24
   call      extractChar1        //t1 <- third char of name
   ld        wq, t2
   aqw_ld    void, (TFTPpayload - data)
   
   ld        t2, t1            //t2 <- third char of name
   call      extractChar1      //t1 <- fourth char of name
   lsl       t1, t1, 8
   
   or        t2, t1, t2       //now we need 'o', 0x0 in high half
   ld        t1, 0x6f
   ror       t1, t1, 8   
   
   or        wq, t2, t1
   

   aqw_ld    void, (TFTPpayload - data + datawordsize)	
   j         setupMessage
	
extractChar1:
   or        t2, t2, t1
extractChar:
   ld        wq, link
	aqw_sub   stkp, stkp, datawordsize
	ror       Temp, Temp, 28 //left 4 = ror 28
	and       t1, Temp, 0xf
	add       t1, t1, "a"
	j         ret
	
failMAC:  //must drain rq to avoid later confusion
   sub      result, result, 1
	jm       emptyMQ //ret
	ld       void, rq
	j        failMAC
	
setupMessage:  //put the MAC address into the DHCP DISCOVER message
   ld        N, 1      //indicate progress
	call      printNum
	aqr_ld    void, (myMACaddress - data)
	aqr_ld    void, (myMACaddress - data) + datawordsize
	aqw_ld    void, (DISCOVERmsg - data) + (18 * datawordsize)
   ld        wq, rq
	aqw_ld    void, (DISCOVERmsg - data) + (19 * datawordsize)
	ld        wq, rq
	
	long_ld    Addr, (DISCOVERmsg - data)
	call       patchHeader

//store the 3 option words into the packet payload
    long_ld    wq, 0x37010135        //parameter request list, DHCP DISCOVER type
    aqw_ld     void, (opt0 - data)
    long_ld    wq, 0x031c0103        //router(03), broadcast address(28),subnet mask(01), paramerer list length(03)
    aqw_ld     void, (opt1 - data)	 
    long_ld    wq, 0x000000ff        //end of options
	 aqw_ld     void, (opt2 - data)

    ld         md1, dUDPmessageLength
    ld         md2, (DISCOVERmsg - data)
	 
	 call sendRcv  //first packet exchange of the protocol
	 
	aqr_ld     void, (rcvBuffer - data)  //check that the exchange worked
	ld         void, rq
   jm         emptyMQ //setupMessage   //retry

	 ld        N, 2
	 call      printNum
	 
   call       checkOffer     //to fill in optTable	 
   aqr_ld     void, (rcvBuffer - data)  //check that the exchange worked
	ld         void, rq
   jm         ret
	ld         N, 3
	call       printNum
   aqr_ld     void, (optMsgType - data)
   sub        void, rq, 2     //DHCP OFFER
   jnz        emptyMQ //ret                   //failed

//Now construct the option words for the DHCP REQUEST packet (little endian)
   long_ld    wq, 0x32030135  //first option word: requested IP address option, DHCP request
   aqw_ld     void, (opt0 - data)
 	
   aqr_long_ld     void, (packetBuffer - data) + (11 * datawordsize) //yiaddr from packet
   ld         Temp, rq
   lsl        t1, Temp, 8
   or         wq, t1, 0x04  //second option word: most significant yiaddr bytes, option length 4
   aqw_ld     void, (opt1 - data)  //store second option word
	
   aqr_ld     void, (optServerID - data)  //DHCP server from received option 54(little-endian)	
   long_ld    t1, 0x00043600
   lsr        Temp, Temp, 24   //low byte of yiaddr
   or         t1, Temp, t1     //t1 now has 3 bytes of the third option
	ld         Temp, rq
   call       byteSwap         //opTable is big-endian, we need little
   lsl        t2, Temp, 24     //ms byte of serverID
   or         wq, t1, t2
   aqw_ld     void, (opt2 - data)  //store third option word
	
   lsr        Temp, Temp, 8    //ls 3 bytes of serverID
   long_ld    t1, 0xff000000
   or         wq, Temp, t1
   aqw_ld     void, (opt3 - data)  //store fourth option word

   ld         md1, dUDPmessageLength
   ld         md2, (DISCOVERmsg - data)	 
	call       sendRcv     //second exchange
	
	ld         N, 4
	call       printNum
	
   call       checkOffer     //to fill in optTable	 
   aqr_ld     void, (rcvBuffer - data)  //check that the exchange worked
	ld         void, rq
   jm         emptyMQ
   aqr_ld     void, (optMsgType - data)
   sub        void, rq, 5    //DHCP ACK
   jnz        ret                   //failed
	
//Save the MAC and IP address in memory	
   aqr_ld     void, (DISCOVERmsg - data) + (18 * datawordsize) //msb(MAC address) (network byte order)
   aqr_ld     void, (DISCOVERmsg - data) + (19 * datawordsize) //lsb(MAC address) (in bits 31:16)
	aqw_ld     void, (myMACaddress - data)
	ld         wq, rq
	aqw_ld     void, (myMACaddress - data) + datawordsize
	ld         wq, rq
   aqr_long_ld     void, (packetBuffer - data) + (11 * datawordsize) //yiaddr from packet
	ld         wq, rq
	aqw_ld     void, (myIPaddress - data)
	j          TFTPclient + 2
 

// ------------------------------------------------------------
//A simple TFTP client.
//The TFTP server is assumed to be running.
// ------------------------------------------------------------


TFTPclient:  
    ld         wq, link
    aqw_sub    stkp, stkp, datawordsize
	 
    long_ld    a1, 0x4000 //clear the file area
    long_ld    count, 0x10000
    call       initMem
	 
    long_ld    Addr, ARPipAddress 
    call       sendARP
	 
    aqr_ld     void, (rcvBuffer - data)  //check that the exchange worked
    ld         void, rq
    jm         ret    //failed. Return to caller
	 
	 ld         N, 5
	 call       printNum

//Now we fill in the TFTP request and ACK messages. Ethernet header first
    long_ld  t1, (packetBuffer - data) + (2 * datawordsize) //Sender hardware address becomes destination MAC address
    aqr_ld     void, t1
    ld         Temp, rq
    call       byteSwap  //put in form suitable for header
    ld         wq, Temp
    aqw_ld     void, (TFTPmessage - data) + (2 * datawordsize)

    ld wq, Temp
    aqw_ld void, (TFTPAckMessage - data) + (2 * datawordsize)
	 
    aqr_add    void, t1, datawordsize  //low 16 bits of SHA in bits 15:0
    ld         Temp, rq
    call       byteSwap
    andn       Temp, Temp, LowHalf
    or         wq, Temp, 0x0800
    aqw_ld     void, (TFTPmessage - data) + (3 * datawordsize)  //second word of Ethernet header

    or wq, Temp, 0x800
    aqw_ld void, (TFTPAckMessage - data) + (3 * datawordsize)

//Now fill in the IP header
    	 
    aqr_ld     void, (myIPaddress - data)
    ld         Temp, rq

    call       byteSwap
    ld         wq, Temp
    aqw_ld     void, (TFTPmessage - data) + (7 * datawordsize)

    ld wq, Temp
    aqw_ld void, (TFTPAckMessage - data) + (7 * datawordsize)
	 
    long_ld    Temp, ARPipAddress
    ld         wq, Temp
    aqw_ld     void, (TFTPmessage - data) + (8 * datawordsize)

    ld wq, Temp
    aqw_ld void, (TFTPAckMessage - data) + (8 * datawordsize)
	 
    ld         Addr, (TFTPmessage - data)
    call       patchHeader  //fill in whichCore, generate checksum
	 
    ld Addr, (TFTPAckMessage - data)
    call patchHeader

//Fill in the UDP header
    aqr_ld     void, 0x22  //the cycle counter, used as my port number
    lsl        Temp, rq, 16
    or         wq, Temp, 69    //source port, destination port
    aqw_ld     void, (TFTPmessage - data) + (9 * datawordsize)

//ready to send/receive

    ld         md1, tUDPmessageLength
    ld         md2, (TFTPmessage - data)	 
	 call       sendRcv  //first packet exchange of the protocol
	 
	 ld         N, 6
	 call       printNum

//We should have received the first block of the file.  
    aqr_ld     void, (rcvBuffer - data)  //check that the exchange worked
    ld         void, rq
    jm         ret    //failed. Return to caller

//We should check that the packet is correct, but for the moment, we'll assume it is.
//The TFTPAckMessage is ready to go, except for the source and destination UDP ports and the
//block number.  We fill in the ports once, from the received packet.  The block
//number changes on each exchange.

    long_ld   t1, (packetBuffer - data) + (5 * datawordsize)  //The source and destination UDP ports
    aqr_ld    void, t1
    aqr_add   void, t1, (2 * datawordsize)  //the opcode and block number
    ld        Temp, rq
    call      byteSwap      //put in format needed for a header
    lsl       t2, Temp, 16  //exchange source and destination ports (roles are reversed)
    lsr       Temp, Temp, 16
    or        wq, Temp, t2
    aqw_ld    void, (TFTPAckMessage - data) + (9 * datawordsize)  //store port address in ACKMessage

blockLoop:	 
    ld        Temp, rq  //block number, opcode
    andn      Temp, Temp, LowHalf
    add       wq, Temp, 0x0400   
    aqw_ld    void, (TFTPpayload1 - data) //store into ACK message payload
	 
//Now copy 512 bytes from packetBuffer + 0x20 to x4000 + (blockNumber * 512)
    call      byteSwap //block number into low half of Temp
    and       Temp, Temp, LowHalf
    sub       Temp, Temp, 1
    lsl       Temp, Temp, 9   //(block number -1) * 512
    long_ld   t2, 0x4000
    add_lsr   t2, t2, Temp, 2    //destination word address
    long_ld   t1, (packetBuffer - data) + 0x20  //source byte address
    lsr       t1, t1, 2   //source word address
    ld        count, 128       //copy 128 words
    call      copyBlock

//Now check the packet length to see if we have done the last block of the file
    aqr_ld    void, (rcvBuffer - data)
    ld        t1, 0x220  //length of a packet with 512 bytes
    sub       void, rq, t1
    jnz       sendFinalAck
	 
    ld         md1, t1UDPmessageLength
    ld         md2, (TFTPAckMessage - data)	 
    call       sendRcv  
    aqr_ld     void, (rcvBuffer - data)  //check that the exchange worked
    ld         void, rq
    jm         ret    //failed. Return to caller
	 
    ld         Char, "."
    call       printCh
	 
    aqr_long_ld  void, (packetBuffer - data) + (7 * datawordsize) //opcode and block length
    j          blockLoop
	 
sendFinalAck:
	 
    aqw_long_ld    void, 0x7f00e //flush the cache
	 

	 
//send a message to the Eternet controller to cause it to send the packet
    ld         t1, EtherCore
    ld         t2, t1UDPmessageLength
    ld         t3, (TFTPAckMessage - data)
    call       sendMessage
	 
//Since each of the packets that expect a reply have an allocation of 2,
//the Ethernet receiver should now be quiescent.  We expect one more
//message confirming the transmission.

    long_ld    count, 50000000   //Timeout. ~10 cycles/iteration.
    call       receiveMessage
    ld         Temp, result      //length is in result 
    jnz        checkLength1      //Should be 1 
    sub        wq, zero, 1       //No reply within timeout. Store -1 in rcvBuffer
    aqw_ld     void, (rcvBuffer - data)
    j          ret               //return without printing "!"
checkLength1:
    sub        void, result, 1  //transmit complete message?
    jnz        emptyRQ
    ld         void, rq         //read the 1-word transmit complete payload from rq
    ld         Char, "!"
    call       printCh	 
    j          ret              //return

 ret:
    aqr_ld   void, stkp
    add      stkp, stkp, datawordsize
    j        rq
	 
/*	 
//A simple test of the lock unit.  Spins trying to acquire lock 0.  When successful, 
//waits 30 cycles, release the lock. Waits another 30 cycles and loops.
//Run it on several cores and watch the Ring with Chipscope
lockTest:
    aqw_ld   void, IO_OUTREG //release the RS232
    ld       wq, 1
    aqw_ld   void, IO_OUTREG
    ld       wq, zero

lockLoop:
   aqr_ld    void, 0x16  //read from IO device 5
	ld        void, rq
	jnz       gotLock
	j         lockLoop
gotLock:
	ld        count, 10
dally:
   sub       count, count, 1
	jnz       dally
   aqw_ld    void, 0x16 //write to device 5 to release
	ld        count, 10
rdally:
	sub       count, count, 1
   jnz       rdally
   j         lockLoop


//Test data cache flush and eviction
FlushTest:
   aqw_long_ld    void, 0x7f00e //entire cache
	j        start
	
InvalTest:
   aqw_long_ld    void, 0xff00e //entire cache
	j       start
	
*/
	
copyBlock:
//copies count words from t1 to t2 (word addresses)
   ld      wq, link
   aqw_sub stkp, stkp, 4
   ld      wq, t1
   ld      wq, t2
   ld      wq, count
//send a message to the copier  
   add_lsl  Temp, EtherCore, 0x31, 5  //dest = EtherCore + 1, length = 3, lsh 5 
   aqw_add  void, Temp, 0x12 //IO device 4 (Messenger)
   ld        Rchksum, rq  //get the received checksum
   j ret   


/* 	 
copyTest:
   ld       wq, link
   aqw_sub  stkp, stkp, 4	 
   ld       Addr, (0x1000 - 4)  //0xfff is the largest 1-instruction (non-jump) constant
   add      Base, Addr, 4
   lsl      DestBase, Base, 1   //DestBase is 2 * Base
   add_lsl  Temp, Addr, 4, 1   //Temp = 0x2000
//initialize the source region (loc = Addr)
initLoop:
   add      wq, Addr, 4
   aqw_add  Addr, Addr, 4
   sub      void, Addr, Temp  //Addr - Temp < 0 => Addr < Temp
   jm       initLoop
	
   add       Temp, Base, DestBase  //Temp = 0x3000
   sub       Addr, DestBase, 4
	
//zero the destination region
zeroLoop:
   ld        wq, zero
   aqw_add   Addr, Addr, 4
   sub       void, Addr, Temp
   jm        zeroLoop;
	
	
   aqw_long_ld    void, 0x7f00e //flush the cache
	
   aqr_ld   void, zero  //wait for the flush to finish
   ld       void, rq    //stalls

   ld      Total, zero  //use Total to count tests

//The test loops through S, D, and L,
//does a copy, compares the checksum with
//one done by hand, and compares the data
 	

// for(S = 0; S < 32, S = S + 4){
//  for(D = 0; D < 32; D = D + 4{
//    for(L = 0; L < 100; L = L + 1{
//      doTest(S, D, L)
//    }
//  }
//}


  ld    S, zero
L1:
  ld    D, zero
L2:
  ld    L, 1
L3:
  call  doTest    //should inline this
  add   L, L, 1
  sub   void, L, 100
  jm    L3
  add   D, D, 4
  sub   void, D, 32
  jm    L2
  add   S, S, 4
  sub   void, S, 32
  jm    L1
  ld    Char, "D"
  call  printCh
  sub    Addr, zero, 4  //prints -4 for Addr on correct termination  
  ld     Expected, Total  //passes done
  j      dataError 

//  j     ret  

doTest:
  ld    wq, link
  aqw_sub stkp, stkp, 4
  andn  Flags, Flags, F_odec    // clear decimal output mode flag
  
  aqw_long_ld    void, 0x7f00e //flush the cache
  aqw_long_ld    void, 0xff00e //invalidate the cache

  aqr_ld   void, zero  //wait for the flush to finish
  ld       void, rq    //stalls

  add_lsr      t1, Base, S, 2  //copier takes word addresses
  add_lsr      t2, DestBase, D, 2
  ld       count, L
  call     copyBlock

checkResults:
   add       Addr, DestBase, D
   sub       Addr, Addr, 4
   add       Expected, Base, S   //expected data
   ld        Checksum, zero  //clear the expected checksum
   ld        count, L        //the length
tLoop:
   aqr_add   Addr, Addr, 4
   and       Temp, Expected, LowHalf  //accumulate the expected checksum
   add       Checksum, Checksum, Temp
   lsr       Temp, Expected, 16
   add       Checksum, Checksum, Temp
   lsr       Temp, Checksum, 16  //carries
   add       Checksum, Checksum, Temp
   and       Checksum, Checksum, LowHalf
   ld        Received, rq
   xor       void, Expected, Received
   jnz       dataError
   add       Expected, Expected, 4
   sub       count, count, 1
   jnz       tLoop
//check the checksum
   xorn      Checksum, Checksum, zero  //complement
	and       Checksum, Checksum, LowHalf //mask low bits
   xor       void, Checksum, Rchksum
   jnz       checksumError
   add       Total, Total, 1
   j         ret	

checksumError:
  ld    Expected, Checksum
  ld    Received, Rchksum
  sub   Addr, zero, 1  //prints -1 for Addr

dataError:
  call  printCRLF
  ld    N, L
  call  printNum
  ld    Char, " "
  call  printCh
  ld    N, D
  call  printNum
  ld    Char, " "
  call  printCh
  ld    N, S
  call  printNum
  ld    Char, " "
  call  printCh
  ld    Char, " "
  call  printCh
  ld    N, Addr
  call  printNum
  ld    Char, " "
  call  printCh
  ld    N, Expected
  call  printNum
  ld    Char, " "
  call  printCh
  ld    N, Received
  call  printNum
  j     start  

  
badLength:
wrongCore:
//extract result words from rq
   ld     void, rq
	sub    result, result, 1
	jnz    wrongCore
      sub    Addr, zero, 2  //prints -2 for Addr
      j      dataError

timeout:
     sub    Addr, zero, 3  //prints -3 for Addr
     ld     Expected, Total  //passes done
     j      dataError 
	
*/

//----------------------------------------------
//Test for the display controller.  Fill the frame buffer with white,
//then with color bars.
//----------------------------------------------

//The test reusus a lot of registers.  This is OK, since it never returns.
color =  $10
dcAddr = $11
delayTime = $12
countX   = $14
addrMsg  = $15
addrXor  = $16
delayRet = $17
//Temp = $13, EtherCore = $20
 
red = 0xff0000
green = 0xff00
blue  = 0xff
yellow = 0xffff00
cyan   = 0xffff
magenta = 0xff00ff
white = 0xffffff
gray  = 0x808080

dcBase =      (0x2000000 - 4)
dcCacheBase = (0x2000000 LSR 5)  //cache line address for the white frame
dcBarBase =   (0x3000000 - 4)   //cache line address for the color bar frame
dcBarXor  =   (0x1000000 LSR 5)  //xor value to switch between frame buffers

fullFrame = (1280 * 1025)

dcTest:
   long_ld dcAddr, dcBase 
   long_ld countX, fullFrame
   long_ld color, gray
   call paint

   long_ld dcAddr, dcBarBase
   ld   count, 1025
lineLoop: call paintLine
   sub count, count, 1
   jnz lineLoop
   
   long_ld addrMsg, dcCacheBase
   long_ld addrXor, dcBarXor
   
//now alternate between the white frame and the color bars
switchFrames:
   xor addrMsg, addrMsg, addrXor
   long_ld count, 50000000      //display a frame repetitively for 1 second.
dcDelay: sub count, count, 1
   jnz dcDelay
//send a message to the copier
   ld       wq, addrMsg  
   add_lsl  Temp, EtherCore, 0x11, 5  //dest = {length (1),EtherCore + 1}, length = 1} lsh 5 
   aqw_add  void, Temp, 0x12 //IO device 4 (Messenger)
   ld       void, rq  //discard the ack
   j  switchFrames

//paint 8 bars, each 160 pixels wide
paintLine: ld delayRet, link
   long_ld color, gray
   call paint160
   long_ld color, red
   call paint160
   long_ld color, green
   call paint160
   long_ld color, blue
   call paint160
   ld   color, 0  //black
   call paint160
   long_ld   color, cyan
   call paint160
   long_ld   color, magenta
   call paint160
   long_ld   color, yellow
   call paint160
   j delayRet    

paint160: ld countX, 160
paint: aqw_add dcAddr, dcAddr, 4
   ld wq, color;
   sub  countX, countX, 1
   jnz  paint
   j link

	 

