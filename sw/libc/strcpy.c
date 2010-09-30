#include <string.h>

char * strcpy(char * dst,const char * str)
{
  char * r = dst;
  for (;;) {
    char c = *str++;
    *dst++ = c;
    if (c == 0) break;
  }
  return r;
}
