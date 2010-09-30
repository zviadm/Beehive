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
        .globl _ffo

_ffo:
        lsr vb,r3,16;  jz B00.15 // bits [00..15] contain first one...
        lsr vb,r3,24;  jz B16.23 // bits [16..23] contain first one...
        lsr vb,r3,28;  jz B24.27 // bits [24..27] contain first one...
        lsr vb,r3,30;  jz B28.29 // bits [28..29] contain first one...
        lsr vb,r3,31;  jz B30    // bit [30] contains first one...
        ld  r1,31-31;  j link

B30:    ld  r1,31-30;  j link

B28.29: lsr vb,r3,29;  jz B28    // bit [28] contains first one...
        ld  r1,31-29;  j link

B28:    ld  r1,31-28;  j link

B24.27: lsr vb,r3,26;  jz B24.25 // bits [24..25] contain first one...
        lsr vb,r3,27;  jz B26    // bit [26] contains first one...
        ld  r1,31-27;  j link

B26:    ld  r1,31-26;  j link

B24.25: lsr vb,r3,25;  jz B24    // bit [24] contains first one...
        ld  r1,31-25;  j link

B24:    ld  r1,31-24;  j link

B16.23: lsr vb,r3,20;  jz B16.19 // bits [16..19] contain first one...
        lsr vb,r3,22;  jz B20.21 // bits [20..21] contain first one...
        lsr vb,r3,23;  jz B22    // bit [22] contains first one...
        ld  r1,31-23;  j link

B22:    ld  r1,31-22;  j link

B20.21: lsr vb,r3,21;  jz B20    // bit [20] contains first one...
        ld  r1,31-21;  j link

B20:    ld  r1,31-20;  j link

B16.19: lsr vb,r3,18;  jz B16.17 // bits [16..17] contain first one...
        lsr vb,r3,19;  jz B18    // bit [18] contains first one...
        ld  r1,31-19;  j link

B18:    ld  r1,31-18;  j link

B16.17: lsr vb,r3,17;  jz B16    // bit [16] contains first one...
        ld  r1,31-17;  j link

B16:    ld  r1,31-16;  j link

B00.15: lsr vb,r3,8;   jz B00.07 // bits [00..07] contain first one...
        lsr vb,r3,12;  jz B08.11 // bits [08..11] contain first one...
        lsr vb,r3,14;  jz B12.13 // bits [12..13] contain first one...
        lsr vb,r3,15;  jz B14    // bit [14] contains first one...
        ld  r1,31-15;  j link

B14:    ld  r1,31-14;  j link

B12.13: lsr vb,r3,13;  jz B12    // bit [12] contains first one...
        ld  r1,31-13;  j link

B12:    ld  r1,31-12;  j link

B08.11: lsr vb,r3,10;  jz B08.09 // bits [08..09] contain first one...
        lsr vb,r3,11;  jz B10    // bit [10] contains first one...
        ld  r1,31-11;  j link

B10:    ld  r1,31-10;  j link

B08.09: lsr vb,r3,9;   jz B08    // bit [08] contains first one...
        ld  r1,31-9;   j link

B08:    ld  r1,31-8;   j link

B00.07: lsr vb,r3,4;   jz B00.03 // bits [00..03] contain first one...
        lsr vb,r3,6;   jz B04.05 // bits [04..05] contain first one...
        lsr vb,r3,7;   jz B06    // bit [06] contains first one...
        ld  r1,31-7;   j link

B06:    ld  r1,31-6;   j link

B04.05: lsr vb,r3,5;   jz B04    // bit [04] contains first one...
        ld  r1,31-5;   j link

B04:    ld  r1,31-4;   j link

B00.03: lsr vb,r3,2;   jz B00.01 // bits [00..01] contain first one...
        lsr vb,r3,3;   jz B02    // bit [02] contains first one...
        ld  r1,31-3;   j link

B02:    ld  r1,31-2;   j link

B00.01: lsr vb,r3,1;   jz B00    // bit [00] contains first one...
        ld  r1,31-1;   j link

B00:    ld  vb,r3;     jz BM1
        ld  r1,31-0;   j link

BM1:    ld  r1,-1;     j link
