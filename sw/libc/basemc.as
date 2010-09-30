    .include  "stdas.as"
// ------------------------------------------------------------
// Program start for multiple cores.  Initialize and jump to main.
// ------------------------------------------------------------
    .code

BITS=10

    .globl     _main
    .globl     _exit

    .globl     main
main:
    andn       zero,zero,zero   // initialize zero

    aqr_ld     vb,0x80000000 ROL 2  // read asli register
    lsr        t1,rq,10             // right align core number
    and        t1,t1,15             // mask to core number
    lsl        t1,t1,BITS           // byte stack per core
    long_ld    sp,stack+(1 LSL BITS)
    add        sp,sp,t1
    
    long_call  _main            // main program
    
_exit:	
    simctrl    1                // exit
    j          _exit




    .data
    .align 128*4
    .blkb (1 LSL BITS)*16
stack:
