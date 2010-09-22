#ifndef _SETJMP_H_
#define _SETJMP_H_

#include "lib/attr.h"

struct ws_jmp_buf {
  unsigned int r9;
  unsigned int r10;
  unsigned int r11;
  unsigned int r12;
  unsigned int r13;
  unsigned int r14;
  unsigned int r15;
  unsigned int r16;
  unsigned int r17;
  unsigned int r18;
  unsigned int r19;
  unsigned int r20;
  unsigned int r21;
  unsigned int r22;
  unsigned int fp;
  unsigned int sp;
  unsigned int link;
};

extern int  ws_setjmp(struct ws_jmp_buf *env);
extern void ws_longjmp(struct ws_jmp_buf *env, int val) __noret__;

#endif
