    .include "stdas.as"
// ------------------------------------------------------------
// Find first one
//
// Entry:
//    r3 = value
//    link = return address into subroutine
//
// Return:
//    r1 = number of leading zeros in value
// ------------------------------------------------------------
    .globl   _ffo

_ffo:
    ld       r2,r3
    jz       ffozero

    ld       r1,0

    lsr      r3,r2,16
    jnz      R3.16
    add      r1,r1,16

    lsr      r3,r2,8
    jnz      R3.8
    add      r1,r1,8

R2.8:
    lsr      r3,r2,4
    jnz      R3.4
    add      r1,r1,4

R2.4:
    lsr      r3,r2,2
    jnz      R3.2
    add      r1,r1,2

R2.2:
    lsr      r3,r2,1
    jnz      link
    add      r1,r1,1

    j        link


R3.16:
    lsr      r2,r3,8
    jnz      R2.8
    add      r1,r1,8

R3.8:
    lsr      r2,r3,4
    jnz      R2.4
    add      r1,r1,4

R3.4:
    lsr      r2,r3,2
    jnz      R2.2
    add      r1,r1,2

R3.2:
    lsr      r2,r3,1
    jnz      link
    add      r1,r1,1

    j        link


ffozero:
    ld       r1,-1
    j        link
