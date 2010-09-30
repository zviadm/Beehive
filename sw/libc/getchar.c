#include <stdio.h>

/* ------------------------------------------------------------
   Get char from the console.
   ------------------------------------------------------------ */
int getchar()
{
  int * IO_ASLI = (int *)0x00000002;
  int v;

  while (((v = *IO_ASLI) & 0x100) == 0)  ;

  v &= 0xff;

  *IO_ASLI = 0x100;

  return v;
}
