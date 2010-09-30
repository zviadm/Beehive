#include <stdio.h>
#include <stdarg.h>
#include <doprnt.h>



/* ------------------------------------------------------------
   Internal subroutine for sprintf.
   ------------------------------------------------------------ */

void
__sprintf_char (char c,void * env)
{
  *(*(char **)env)++ = c;
}





/* ------------------------------------------------------------
   Process a format string, taking varargs, and write the output
   characters into a buffer (which is assumed to be large enough).
   ------------------------------------------------------------ */

int
sprintf (char * buf,const char * format, ...)
{
  va_list args;

  va_start(args,format);
  int n =_doprnt(format,args,__sprintf_char,&buf);
  va_end(args);

  *buf = 0;

  return n;
}
