.code
void     = $0
zero     = $0
.assume  zero, 0
count    = $1
base     = $2
linkAddr = $3
addr     = $4
rqCount  = $5

invalIcache = 0x7FFFF000 //2GB - 4KB

// inv=0 cnt=127 line=0 dev=3
FLUSHALL = (0 LSL 19) + (127 LSL 12) + (0 LSL 5) + (3 LSL 2) + 2
 
// inv=1 cnt=127 line=0 dev=3
INVALALL = (1 LSL 19) + (127 LSL 12) + (0 LSL 5) + (3 LSL 2) + 2

// type=1 len=1 dst=1 dev=4
STOPACKMSG = (1 LSL 15) + (1 LSL 9) + (1 LSL 5) + (4 LSL 2) + 2
 


  ld       zero, 0 //nop at location 0.
  ld       wq, $1  //put the registers in WQ
  ld       wq, $2
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

//put savedLink and savedPC into wq
  j7       3        //link <- savedLink
  ld       wq, link
  j7       2        //link <- savedPC
  ld       wq, link

//issue 30 writes to store the registers, savedLink, and savedPC to words 1..30 of the save area.
  ld       count, 30
  j7       1        //link <- save area
saveRegs:
  aqw_add  link, link, 4
  sub      count, count, 1
  jnz      saveRegs

  ld       linkAddr, link  //linkAddr is used for subsequent addressing
//copy rq entries into wq and write them to memory until rq is empty
//count the number of entries with count (now = 0)
rqToWq:
  j7       4    //link <- 0 if rq empty, else 1
  ld       void, link  //test it
  jz       rqSaved
  ld       wq, rq
  aqw_add  linkAddr, linkAddr, 4
  add      count, count, 1
  j        rqToWq
  
rqSaved:
  ld       wq, count  //save count in word 0 of the save area
  j7       1   //link <- save area
  aqw_ld   link, link
  
//save is now complete

//build the table of instructions at invalIcache
long_ld    addr, invalIcache
sub        addr, addr, 32
ld         count, 127  //first 127 entries (32 bytes apart) get the jump instruction

buildTable:
long_ld    wq, 0xf800820c //J PC ADD 00000020
aqw_add    addr, addr, 32
sub        count, count, 1
jnz        buildTable
long_ld    wq, 0xf000030c  //J LINK OR 00000000
aqw_add    addr, addr, 32
 
// flush and invalidate the data cache
 
  aqw_long_ld  void,FLUSHALL
  aqw_long_ld  void,INVALALL
 
// send a message to the master, indicating we've stopped
 
       ld           wq,0      // message payload
       aqw_long_ld  void,STOPACKMSG
 
// ------------------------------------------------------------
// wait for the master to start us
// ------------------------------------------------------------

waitStart:
  j7     5  //link <- 1 if running, else 0
  ld     void, link   //test it
  jnz    restore
  j      waitStart

restore:
  j7       1 //link <- save area
  sub      link, link, 4  
  ld       count, 31  //issue reads for RQ count, registers 1-28, savedLink, savedPC
readRegs:
  aqr_add  link, link, 4
  sub      count, count, 1
  jnz      readRegs
  
reloadRegs:
  ld       $28, rq    //put RQ count into r28
  ld       $1, rq     //load registers 1-27
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

//rq now has r28, savedLink, savedPC
//$28 contains the number of RQ entries to restore.
//continue reading until $28 < 0. 
loadRQ:
  sub      $28, $28, 1 //all RQ entries read?
  jm       rqDone
  aqr_add  link, link, 4
  j        loadRQ
  
rqDone:
//rq contains r28, savedLink, savedPC, and the RQ entries.

//invalidate the instruction cache
 long_call invalIcache

 ld        $28, rq    //load r28
 ld        link, rq   //load link
 j         rq         //transfer to user code.

