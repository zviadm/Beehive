#include <stdio.h>


/* ------------------------------------------------------------
   Print an asciz string on the console.
   ------------------------------------------------------------ */
int puts(const char * s)
{
  for (;;) {
    int c = *s++;
    if (c == 0) return 0;
    putchar(c);
  }
}
