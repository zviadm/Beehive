#include <string.h>

/* ------------------------------------------------------------
   Search memory starting at *SRC looking for the character C.

   The search ends with first occurrence of C, or after N characters.
   In particular, the NUL character does not terminate the search.

   If the character C is found within N characters, a pointer to the
   character is returned.  Otherwise, NULL is returned.
   ------------------------------------------------------------ */

void * memchr (const void * SRC,int C,size_t N)
{
  const unsigned char * src = SRC;
  const unsigned char c = C;

  const unsigned char * end = src + N;

  while (src != end) {
    if (c == *src)  return (void *)src;
    src += 1;
  }

  return 0;
}
