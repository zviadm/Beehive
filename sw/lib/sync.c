#include <string.h>

#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/sync.h"

void barrier_init(struct barrier *b, int waiters)
{
  memset(b, 0, sizeof(*b));
  b->waiters = waiters;
  cache_flushMem(b, sizeof(*b));
}

void barrier_wait(struct barrier *b)
{
  int g, w, i, d;

  g = ++b->gen[corenum()].v;
  cache_flushMem(&b->gen[corenum()].v, sizeof(b->gen[corenum()].v));

  for (w = 0; w < b->waiters;) {
    for (w = 0, i = 0; i < MCCOREN; i++) {
      cache_invalidateMem(&b->gen[i].v, sizeof(b->gen[i].v));
      d = b->gen[i].v - g;
      if (d == 0 || d == 1)
        w++;
      if (d < -1 || d > 1)
        die("barrier_wait: distance %d", d);
    }
  }
}
