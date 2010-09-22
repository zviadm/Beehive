#include <stdarg.h>
#include <stdio.h>
#include <doprnt.h>

#include "shared/intercore.h"
#include "lib/attr.h"
#include "lib/lib.h"

static void __printf_char(char c,void * env)
{
  putchar(c);
}

int vprintf(const char *format, va_list ap)
{
  return _doprnt(format, ap, __printf_char, 0);
}

void die(const char* errstr, ...) 
{
  va_list ap;
    
  icSema_P(sem_xprintf);
  va_start(ap, errstr);
  vprintf(errstr, ap);
  va_end(ap);

  printf("\n%u is dead\n", corenum());
  icSema_V(sem_xprintf); 
  for (;;);
}
