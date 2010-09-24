#include <string.h>
#include <stdio.h>

#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

#define SOL4

#ifdef SOL4
enum { barrier_debug = 0 };

unsigned nbarrier CACHELINE;
unsigned ngen CACHELINE;
#endif

void barrier(void)
{
#ifdef SOL4
// Barrier implementation using shared memory.
// Should we ask the students to do one with broadcast too?
  unsigned mygen;

  icSema_P(sem_barrier_mutex);
  cache_invalidateMem(&nbarrier, sizeof(nbarrier));
  cache_invalidateMem(&ngen, sizeof(ngen));

  if (barrier_debug) xprintf("%u: rgn_barrier enter %u %u %u\n", 
                        corenum(), enetCorenum()-2, ngen, nbarrier);

  mygen = ngen;
  nbarrier++;
  cache_flushMem(&nbarrier, sizeof(nbarrier));

  for (;;) {
    if (ngen != mygen)
      break;

    if (nbarrier >= enetCorenum() -2)
      break;

    if (barrier_debug) xprintf("%u: rgn_barrier wait %u %u %u\n", 
      corenum(), enetCorenum()-2, ngen, nbarrier);

    icSema_V(sem_barrier_mutex);
    icSema_P((mygen & 1) ? sem_barrier_wait1 : sem_barrier_wait0);
    icSema_P(sem_barrier_mutex);

    cache_invalidateMem(&ngen, sizeof(ngen));
    cache_invalidateMem(&nbarrier, sizeof(nbarrier));

    if (barrier_debug) xprintf("%u: rgn_barrier wait done %u %u %u\n", 
      corenum(), enetCorenum()-2, ngen, nbarrier);
  }

  if (ngen == mygen) {
    nbarrier = 0;
    ngen++;

    cache_flushMem(&nbarrier, sizeof(nbarrier));
    cache_flushMem(&ngen, sizeof(ngen));
  }

  if (barrier_debug) xprintf("%u: rgn_barrier return %u %u %u\n", 
    corenum(), enetCorenum()-2, ngen, nbarrier);
  icSema_V((mygen & 1) ? sem_barrier_wait1 : sem_barrier_wait0);
  icSema_V(sem_barrier_mutex);
#endif
}
