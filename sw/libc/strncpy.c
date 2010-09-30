#include <string.h>

char * strncpy(char * dst,const char * str,size_t n)
{
  char * r = dst;
  while (n != 0) {
    char c = *str++;
    if (c == 0) break;
    *dst++ = c;
    --n;
  }
  while (n != 0) {
    *dst++ = 0;
    --n;
  }
  return r;
}
