#include <string.h>

size_t strlen(const char * str)
{
  int istr = (int)str;

  // Scan bytes until aligned to word bounary.

  while ((istr & 3) != 0) {
    if (*(char *)istr == 0) return (size_t)(istr - (int)str);
    istr += 1;
  }

  // Scan words

  for (;;) {
    unsigned int w = *(unsigned int *)istr;
    if (((w >> 0) & 255) == 0) return (size_t)(istr - (int)str);
    if (((w >> 8) & 255) == 0) return (size_t)(istr - (int)str + 1);
    if (((w >> 16) & 255) == 0) return (size_t)(istr - (int)str + 2);
    if (((w >> 24) & 255) == 0) return (size_t)(istr - (int)str + 3);
    istr += 4;
  }
}
