#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/meters.h"
#include "lib/barrier.h"

#define DEBUG 0

void mc_init(void);
void mc_main(void);

void test1(void (*f)(void), const char *type);

struct state {
  int instance;
  int cache_line[63];
} c_[16];

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());  
}

void mc_main()
{
  xprintf("[%02u]: mc_main\n", corenum());
  test1(sm_barrier, "shared memory");
  test1(hw_barrier, "hardware");
}

void test1(void (*barrier)(void), const char *type) 
{
  if (corenum() == 2) { 
    xprintf("[%02u]: test1 for %s barrier start\n", corenum(), type);
    barrier();
    meters_start();
  } else {
    barrier();
  }

  for (unsigned int i = 0; i < 10; i++) {
    barrier();

    // record i went through
    c_[corenum()].instance++;
    cache_flushMem(&c_[corenum()], sizeof(struct state));

    if (DEBUG) 
      xprintf("[%02u]: passed barier and increased state %u\n", corenum(), i);
      
    barrier();

    for (unsigned int j = 2; j < enetCorenum(); j++) {
      int jinstance;
      cache_invalidateMem(&c_[j], sizeof(struct state));
      jinstance = c_[j].instance;
      if (jinstance != c_[corenum()].instance) {
        xprintf("[%02u]: %s barrier failed: my instance is %d and %d's is %d\n", 
          corenum(), type, c_[corenum()].instance, j, jinstance);
        assert(0);
      }
    }
  }

  if (corenum() == 2) {
    meters_report();
    barrier();
    xprintf("[%02u]: test1 for %s barrier passed\n", corenum(), type);
  } else {
    barrier();
  }
}
