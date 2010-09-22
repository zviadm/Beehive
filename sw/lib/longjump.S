.include "stdas.as"

#define STORE_WORD(dest, off, src) \
  aqw_add vb, dest, off * 4;       \
  ld      wq, src

#define LOAD_WORD(src, off, dest) \
  aqr_add vb, src, off * 4;       \
  ld      dest, rq

.code
.globl  _ws_setjmp
_ws_setjmp:
  STORE_WORD(r3, 0, r9)
  STORE_WORD(r3, 1, r10)
  STORE_WORD(r3, 2, r11)
  STORE_WORD(r3, 3, r12)
  STORE_WORD(r3, 4, r13)
  STORE_WORD(r3, 5, r14)
  STORE_WORD(r3, 6, r15)
  STORE_WORD(r3, 7, r16)
  STORE_WORD(r3, 8, r17)
  STORE_WORD(r3, 9, r18)
  STORE_WORD(r3, 10, r19)
  STORE_WORD(r3, 11, r20)
  STORE_WORD(r3, 12, r21)
  STORE_WORD(r3, 13, r22)
  STORE_WORD(r3, 14, fp)
  STORE_WORD(r3, 15, sp)
  STORE_WORD(r3, 16, link)
  
  ld  r1,0
  j  link

.globl  _ws_longjmp
_ws_longjmp:
  LOAD_WORD(r3, 0, r9)
  LOAD_WORD(r3, 1, r10)
  LOAD_WORD(r3, 2, r11)
  LOAD_WORD(r3, 3, r12)
  LOAD_WORD(r3, 4, r13)
  LOAD_WORD(r3, 5, r14)
  LOAD_WORD(r3, 6, r15)
  LOAD_WORD(r3, 7, r16)
  LOAD_WORD(r3, 8, r17)
  LOAD_WORD(r3, 9, r18)
  LOAD_WORD(r3, 10, r19)
  LOAD_WORD(r3, 11, r20)
  LOAD_WORD(r3, 12, r21)
  LOAD_WORD(r3, 13, r22)
  LOAD_WORD(r3, 14, fp)
  LOAD_WORD(r3, 15, sp)
  LOAD_WORD(r3, 16, link)

  ld  r1, r4
  j  link
