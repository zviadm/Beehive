#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

void mc_init(void);
void mc_main(void);
void produceConsume(int use_cache_push);

static const unsigned int kPushSize = 256 * 1024;
int* test_numbers CACHELINE;

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());
  if (corenum() == 2) {
    test_numbers = (int*)malloc(kPushSize * sizeof(int));
  }
  produceConsume(0);
  produceConsume(1);  
}

void produceConsume(int use_cache_push) {
  if (corenum() == 2) {
    for (unsigned int i = 0; i < kPushSize; i++) test_numbers[i] = i;
  }
  
  unsigned int kreal = 0;
  for (unsigned int i = 0; i < kPushSize; i++) kreal += i;

  hw_barrier();
  if ((corenum() == 2) & use_cache_push) {
    for (unsigned int i = 3; i <= nCores(); i++) {
      cache_pushMem(i, test_numbers, kPushSize * sizeof(int));
    }
  }
  hw_barrier();
  const unsigned int start = *cycleCounter;
  if (corenum() == 2 | corenum() == 3 | corenum() == 4) {
    unsigned int k = 0;
    for (unsigned int i = 0; i < kPushSize; i++) k += test_numbers[i];
    assert(kreal == k);
  }
  hw_barrier();
  const unsigned int end = *cycleCounter;

  if (corenum() == 2) {
    xprintf("[%02u]: Done, use_cache_push: %d, run time: %u cycles\n", 
      corenum(), use_cache_push, end - start);  
  }
}
