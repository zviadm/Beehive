#include <stdio.h>

/* ------------------------------------------------------------
   Print char on the console.

   In case of '\n', first print '\r';
   ------------------------------------------------------------ */
int putchar(int c)
{
  int * IO_ASLI = (int *)0x00000002;
  int v;

  int d = 0;
  if (c == '\n') { d = c; c = '\r'; }

  for (;;) {
    while (((v = *IO_ASLI) & 0x200) == 0)  ;
    
    c &= 0xff;
    c |= 0x200;
    
    *IO_ASLI = c;
    
    c = d;
    if (c == 0) return 0;
    d = 0;
  }
}
