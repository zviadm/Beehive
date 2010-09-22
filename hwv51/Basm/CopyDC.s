 
// © Copyright Microsoft Corporation, 2008, 2009, 2010

/* This is the code for the SimpleRisc connected to the block copy/display control unit.
The data memory is a 64-word RAM.
The instruction memory is a 1KW ROM.

The core doesn't contain an RS232 interface, since it only needs to do a few
simple things. In addition to doing copies, it also initializes the Chrontel
chip used by the display controller, and receives buffer addresses for the 
display controller from client cores.
*/

//register names:
zero   = $0
void   = $1
IObase = $2
Checksum = $3
MsgHdr   = $4
Temp   = $5
Flags  = $6

//Flag bits:
vfpPending = 1  //waiting for vertical front porch
msgPending = 2  //We acked a previous FB message and then got another one.
//we can't send it to displayAddr and ack it until the controller has taken
//the earlier value (at lastPixel, which starts vfp).

Xdata  = $7  //I2C write bit, register number, value for Chrontel
FBaddr = $8  //Frame Buffer (cache line) address LSH 2
Stkp   = $9
DlyCnt = $10
I2Cbyte = $11
I2Cmask = $12
SaveLink = $13  //we don't use the stack (in anticipation of removing the data memory entirely).
StartLink = $14
StopLink = $15
SendLink = $16
SendB1Link = $17
ChLink     = $18
FBclient   = $19  //provider of the FB value
pendingFB  = $20  //FB value



//Constants for I2C SCL, SDA values
i00 = 3 //SCL 0, SDA 0
i0Z = 2 //SCL 0, SDA Z
iZ0 = 1 //SCL Z, SDA 0
iZZ = 0 //SCL Z, SDA Z. This is the default (reset) state.

//Constants for I2C delays
halfBit    = 42     //2600ns (400 KHz) / 30 ns. = 87.  Half bit is 43.5. Use smaller because of loop overhead
quarterBit = 21
deviceAddress = 0xec //From Chrontel spec. 

// ------------------------------------------------------------
// Memory mapped IO definitions
// ------------------------------------------------------------
    abs    0x80000000
IO_:

// ------------------------------------------------------------
// Code segment
// ------------------------------------------------------------
    code
    word     0
first:
    andn     zero, zero, zero
    assume   zero, 0          // henceforth assume it
    long_ld  IObase, IO_      // initialize IObase
    assume   IObase, IO_      // henceforth assume it
    ld       pendingFB, zero  //blank frame initially


//0x1000000 is the default FB byte address (used in Master.s)
//This shifted right by 5 to get the cache line address, then shifted left 2 for SCLx, SDAx.  Net shift = 3, so
//0x200000  is the default FB address

    ld  FBaddr, zero            //default FB (cache line)address LSH 2
    ld       Stkp, 0x3f         //end of (small) data memory
    call     setupChrontel      //load the parameters into the Chrontel (one time only)

start:
   aqr_add  void, IObase, 4   //read the message queue
   ld       MsgHdr, rq
   jz       waitVfp
//MsgHdr has the length in bits 5:0 and the source core in bits 13:10.
//the length is 3 for copy commands, 1 for FB addresses
   and   Temp, MsgHdr, 0x3f  //message length
   sub   void, Temp, 3 
   jz    doCopy
   sub   void, Temp, 1
   jz    getFBvalue
   
   j     .     //halt

getFBvalue:
   lsr   FBclient, MsgHdr, 10      //source core
   lsl   pendingFB, rq, 2          //the FB address aligned to the displayAddress register
   and   void, Flags, vfpPending   //if vfpPending is true, the D.C. hasn't taken an earlier address
   jz    waitNoVfp
   or    Flags, Flags, msgPending  //D.C. hasn't taken the previous address. Must wait until it does so.
   j     waitVfp
   
waitNoVfp:
   aqr_ld void, IObase  //device 0 returns the vfp bit
   ld    void, rq
   jnz   waitNoVfp
//vfp is now zero, send pendingFB to the D.C.
   ld    wq, pendingFB
   aqw_add void, IObase, 2
//check for vfp still zero, to ensure the D.C. will get the correct value
   aqr_ld void, IObase
   ld     void, rq
   jnz    waitNoVfp  //vfp went high. We must wait for it do go low and try again
   
//set vfpPending and send an ack to the client
   or    Flags, Flags, vfpPending
   ld    wq, zero  //zero payload
   lsl   FBclient, FBclient, 3
   or    FBclient, FBclient, 0x84    //length = 1, I/O device 4 (messenger)
   aqw_add void, IObase, FBclient //send the message
   
waitVfp:
   and   void, Flags, vfpPending
   jz    start
   aqr_ld void, IObase
   ld    void, rq
   jz    start
   andn  Flags, Flags, vfpPending //clear vfpPending
   and   void, Flags, msgPending
   jz    start
   andn  Flags, Flags, msgPending
   j     waitNoVfp
       
doCopy:
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
   ror      Checksum, rq, 1  //bit 0 is the busy bit, next 16 bits are the checksum
   jm       checkBusy
   ld       wq, Checksum  //send it back to the client
   lsl      Temp, MsgHdr, 3     //the requesting core into bits 3:6 (message destination) 
   or       Temp, Temp, 0x84    //length = 1, I/O device 4 (messenger)
   aqw_add void, IObase, Temp //send the message
   j        waitVfp


setupChrontel:    //send parameters to Chrontel
   ld     ChLink, link
   long_ld Xdata, 0xa109 //DAC control := 09
   call   sendI2C
   long_ld Xdata, 0xb306 //DVI charge pump := 06 (Table 10 of spec)
   call   sendI2C
   long_ld Xdata, 0xb426 //DVI PLL divider := 0x26
   call   sendI2C
   long_ld Xdata, 0xb6a0 //DVI PLL filter := 0xa0
   call   sendI2C
   long_ld Xdata, 0xc9c0 //Power Management - DVI normal
   call   sendI2C
   j     ChLink

sendI2C:
//send a start, 
//send the device address byte,
//send Xdata byte 1 as the register address,
//send Xdata byte 0 as the register data,
//send a stop.

   ld   SendLink, link
   call sendStart
   ld   I2Cbyte, deviceAddress
   call sendB1
   lsr  I2Cbyte, Xdata, 8
   call sendB1
   ld   I2Cbyte, Xdata
   call sendB1
   call sendStop
   j    SendLink
    

delayHalf: 
    ld  SaveLink, link //REMEMBER: on this core, jumps smash the link.
    ld DlyCnt, halfBit
delayH1:
    sub DlyCnt, DlyCnt, 1  //Delay 3 cycles (30ns) * DlyCnt. DlyCnt > 0.
    jnz delayH1
    j   SaveLink

delayQuarter:
    ld SaveLink, link
    ld  DlyCnt, quarterBit
delayQ1:
    sub DlyCnt, DlyCnt, 1  //Delay 3 cycles (30ns) * DlyCnt. DlyCnt > 0.
    jnz delayQ1
    j   SaveLink

sendB1:
    ld      SendB1Link, link
    ld      I2Cmask, 256
sendB1loop:
    ror     I2Cmask, I2Cmask, 1
    jm      getAck
    call    delayQuarter
    and     void, I2Cmask, I2Cbyte
    jnz     sendOne 
sendZero:
    or      wq, FBaddr, i00
    aqw_add void, IObase, 2
    j       sent
sendOne:
    or      wq, FBaddr, i0Z
    aqw_add void, IObase, 2
sent:
    call    delayQuarter
    and     void, I2Cmask, I2Cbyte
    jnz     sentOne
sentZero:
    or      wq, FBaddr, iZ0
    aqw_add void, IObase, 2
    j       sentXX
sentOne:
    or      wq, FBaddr, iZZ
    aqw_add void, IObase, 2
sentXX:
    call    delayHalf
    or      wq, FBaddr, i0Z
    aqw_add void, IObase, 2
    j       sendB1loop

getAck:
    call    delayHalf
    or      wq, FBaddr, iZZ
    aqw_add void, IObase, 2
    call    delayHalf
    or      wq, FBaddr, i0Z
    aqw_add void, IObase, 2
    j         SendB1Link

//A start condition is SDA falling while SCL is high (normally, SDA cnanges only when SCL = 0)
//On entry, SCL = Z, SDA = Z
//On exit,  SCL = 0, SDA = Z
sendStart:
   ld      StartLink, link
   or      wq, FBaddr, i0Z
   aqw_add void, IObase, 2
   call    delayHalf
   or      wq, FBaddr, iZZ
   aqw_add void, IObase, 2
   call    delayQuarter
   or      wq, FBaddr, iZ0
   aqw_add void, IObase, 2
   call    delayQuarter
   or      wq, FBaddr, i0Z
   aqw_add void, IObase, 2
   j  StartLink  


//A stop condition is SDA rising while SCL is high (normally, SDA cnanges only when SCL = 0)
//On entry, SCL = 0, SDA = Z
//On exit,  SCL = Z, SDA = Z
sendStop:
   ld      StopLink, link
   or      wq, FBaddr, i00
   aqw_add void, IObase, 2
   call    delayHalf
   or      wq, FBaddr, iZ0
   aqw_add void, IObase, 2
   call    delayQuarter
   or      wq, FBaddr, iZZ
   aqw_add void, IObase, 2
   call    delayQuarter
   j       StopLink
  


  
        