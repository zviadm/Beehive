#include <string.h>

void bzero(void * ptr,size_t n)
{
  int iptr = (int)ptr;

  // Zero bytes until aligned to word bounary

  while (n != 0 && (iptr & 3) != 0) {
    *(char *)iptr = 0;
    iptr += 1;
    --n;
  }

  // Zero words

  size_t n4 = n >> 2;
  while (n4 != 0) {
    *(int *)iptr = 0;
    iptr += 4;
    --n4;
  }

  // Zero remaining bytes

  n = n & 3;
  while (n != 0) {
    *(char *)iptr = 0;
    iptr += 1;
    --n;
  }
}
