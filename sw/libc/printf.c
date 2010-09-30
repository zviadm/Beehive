#include <stdio.h>
#include <stdarg.h>
#include <doprnt.h>



/* ------------------------------------------------------------
   Internal subroutine for printf.
   ------------------------------------------------------------ */

void
__printf_char (char c,void * env)
{
  putchar(c);
}





/* ------------------------------------------------------------
   Process a format string, taking varargs, and print the output
   characters.
   ------------------------------------------------------------ */

int
printf (const char * format, ...)
{
  va_list args;

  va_start(args,format);
  int n =_doprnt(format,args,__printf_char,0);
  va_end(args);

  return n;
}
