#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/meters.h"

#define NMEMS    1024

void mc_init(void);
void mc_main(void);

void mc_init(void) 
{
}

void mc_main(void) 
{
  if (corenum() != 2)
    return;

  __mcalign__ unsigned int *a;

  xprintf("corenum %u\n", corenum());

  a = malloc(sizeof(*a) * NMEMS);
  if (a == NULL)
    die("malloc");
  cache_invalidateMem(a, sizeof(*a) * NMEMS);

  meters_start();
  
  for (unsigned int i = 0; i < NMEMS; i++)
    a[i] = 0xdeadface;

  cache_flushMem(a, sizeof(*a) * NMEMS);
  
  meters_report();
}
