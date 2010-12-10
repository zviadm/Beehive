#include <stdlib.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

#include "lib/mrand.h"

/* ----------------------------------------------------------------------
 * Linear congruential pseudo-random number generator from Numerical
 * Recipes. This implementation is modified to have good performance with
 * multiple cores.
 * ---------------------------------------------------------------------- */
int mrand_r (unsigned int * ptrseed);

int mrand_r (unsigned int * ptrseed)
{
  unsigned int s = (*ptrseed * 1664525U) + 1013904223U;
  *ptrseed = s;
  return (int)(s & (unsigned int)RAND_MAX);
}

DEFINE_PER_CORE(unsigned int, seed);

int mrand (void)
{
  return rand_r(&my(seed));
}

void msrand (unsigned int s)
{
  my(seed) = s;
}
