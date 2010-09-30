    .include  "stdas.as"
// ------------------------------------------------------------
// Program start.  Initialize and jump to main.
// Includes memory reserved by bootstrap code for save areas
// ------------------------------------------------------------
    .code

    .globl     _main
    .globl     _exit
    .globl     _saveArea

    .globl     main
main:
    andn       zero,zero,zero   // initialize zero
    long_ld    sp,stack         // initialize sp
    
    long_call  _main            // main program
    
_exit:	
    simctrl    1                // exit
    j          _exit

    .align 128
_saveArea:			// start of save area for core #1
    .blkw 63*128
saveAreaEnd:

    .data
    .blkw 200
stack:
