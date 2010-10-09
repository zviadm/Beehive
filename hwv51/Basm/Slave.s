.code
/* The slave stop/start code.

When the system is reset, the program starts at location 0,
waits 10 seconds, then dumps the state. The copy of the code
that the master puts in memory when restarting the slave
doesn't have this delay.  It is provided to give the user
time to type "1s" to give the RS232 to the master before
the state is dumped.

The code uses only self-relative branches, since it will
also be assembled into the data segment of the master, and 
named branch destinations would have the wrong offset.
*/

void     = $0
zero     = $0
.assume  zero, 0
count    = $1
base     = $2
linkAddr = $3
addr     = $4
rqCount  = $5

memsize = 0x80000000   // size of main memory = 2GB
invalByteAddress = memsize - 0x1000 //used when building the table
invalWordAddress = (invalByteAddress LSR 2) // used to call
	
//invalWordAddress = 0x1ffffc00 //(2GB - 4KB)/4.  
//invalByteAddress = 0x7ffff000 //used when building the table

// inv=0 cnt=127 line=0 dev=3
FLUSHALL = (0 LSL 19) + (127 LSL 12) + (0 LSL 5) + (3 LSL 2) + 2
 
// inv=1 cnt=127 line=0 dev=3
INVALALL = (1 LSL 19) + (127 LSL 12) + (0 LSL 5) + (3 LSL 2) + 2

// type=1 len=1 dst=1 dev=4
STOPACKMSG = (1 LSL 15) + (1 LSL 9) + (1 LSL 5) + (4 LSL 2) + 2


 ld       zero, 0 //nop at location 0.
//loop_forever:
//  ld       void, 0
//  j        loop_forever

// long_ld  link, 300000000  //wait 10 seconds
//memLoop:
//  sub      link, link, 1
//  jnz      .-1

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
       j7      2  // link <- savedPC
       ld      wq,link      // message payload
       aqw_long_ld  void,STOPACKMSG
 
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
//rq now contains r28, r29, savedLink, savedPC, and the RQ entries.

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
  j7    6 //break with 3 entries in rq
  ld    void, rq
  ld    void, rq
loopForever:
  ld    $1, 5
  ld    $2, 6
  j     .-2
