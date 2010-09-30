#include <stdlib.h>


/* ----------------------------------------------------------------------
 * Linear congruential pseudo-random number generator from Numerical
 * Recipes.
 * ---------------------------------------------------------------------- */


int rand_r (unsigned int * ptrseed)
{
  unsigned int s = (*ptrseed * 1664525U) + 1013904223U;
  *ptrseed = s;
  return (int)(s & (unsigned int)RAND_MAX);
}



static unsigned int seed;



int rand (void)
{
  return rand_r(&seed);
}



void srand (unsigned int s)
{
  seed = s;
}
