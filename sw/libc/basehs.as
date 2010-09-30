    .include  "stdas.as"
// ------------------------------------------------------------
// Program start.  Initialize and jump to main.
// Set up the stack pointer at the high end of data memory.
// ------------------------------------------------------------
    .code

    .globl     _main
    .globl     _exit

    .globl     main
main:
    andn       zero,zero,zero   // initialize zero
    ld         sp,0xfffffffc    // initialize sp
    
    long_call  _main            // main program
    
_exit:	
    simctrl    1                // exit
    j          _exit
