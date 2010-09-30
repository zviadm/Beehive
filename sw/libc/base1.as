    .include  "stdas.as"
// ------------------------------------------------------------
// Program start.  Initialize and jump to main.
// ------------------------------------------------------------
    .code

    .globl     _main
    .globl     _exit

    .globl     main
main:
    andn       zero,zero,zero   // initialize zero
    long_ld    sp,stack         // initialize sp
    
    long_call  _main            // main program
    
_exit:	
    simctrl    1                // exit
    j          _exit




    .data
    .blkw 200
stack:
