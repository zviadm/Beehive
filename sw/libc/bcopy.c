#include <string.h>

void bcopy(const void * in,void * out,size_t n)
{
  int isrc = (int)in;
  int idst = (int)out;

  if (((isrc ^ idst) & 3) == 0) {

    // "in" and "out" have same byte alignment.
    // Copy bytes until aligned to word bounary.

    while (n != 0 && (isrc & 3) != 0) {
      *(char *)idst = *(char *)isrc;
      isrc += 1;
      idst += 1;
      --n;
    }

    // Copy words

    size_t n4 = n >> 2;
    while (n4 != 0) {
      *(int *)idst = *(int *)isrc;
      isrc += 4;
      idst += 4;
      --n4;
    }

    // Remaining bytes
    n = n & 3;
  }

  // Copy bytes.

  while (n != 0) {
    *(char *)idst = *(char *)isrc;
    isrc += 1;
    idst += 1;
    --n;
  }
}
