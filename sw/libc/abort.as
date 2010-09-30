        .include "stdas.as"

        .globl   _puts
        .globl   _abort

        .code
_abort:
        ld       r9,link      // keep return address for debugging
        long_ld  r3,msg
        long_call _puts

        simctrl  4            // dump registers (note return addres in r9)
L1:
        simctrl  1            // exit simulator
        j        L1

       .data
msg:   .string   "!abort!"

