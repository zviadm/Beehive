#include <string.h>

/* ------------------------------------------------------------
   Compare successive characters S1[i] v.s. S2[i] for i from 0 up to
   N-1.

   If all are the same, return 0.  Otherwise, at the first difference,
   return an integer less than zero if S1[i] < S2[i] or an integer
   greater than zero if S1[i] > S2[i].
   ------------------------------------------------------------ */

int memcmp (const void * S1,const void * S2,size_t N)
{
  const char * s1 = S1;
  const char * s2 = S2;

  --s1;
  --s2;

  while (N > 0) {
    int d = *++s1 - *++s2;
    if (d != 0) return d;
    N--;
  }
  return 0;
}
