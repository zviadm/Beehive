#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "lib/barrier.h"
#include "lib/lib.h"
#include "lib/meters.h"
#include "shared/intercore.h"

#define NMEMS    1024

void mc_init(void);
void mc_main(void);

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());  
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());
  hw_barrier();
  
  __mcalign__ unsigned int *a;  
  a = malloc(sizeof(*a) * NMEMS);
  assert(a != NULL);
  
  dcache_meters_start();  
  for (unsigned int i = 0; i < NMEMS; i++)  a[i] = 0xdeadface;  
  dcache_meters_report();
}
