#include <string.h>


/* This function copies N bytes from the memory region pointed to by
IN to the memory region pointed to by OUT.  If the regions overlap,
the behavior is undefined.  `memcpy' returns a pointer to the first
byte of the OUT region. */



void * memcpy(void *OUT, const void *IN, size_t N)
{
  size_t n = N;
  int isrc = (int)IN;
  int idst = (int)OUT;

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

  return OUT;
}
