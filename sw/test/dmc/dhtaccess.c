#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"
#include "lib/mrand.h"

void mc_init(void);
void mc_main(void);

void access_test(int dht_size, int iterations);

const unsigned int kMaxNumbers = 1 << 20;
volatile int* test_numbers CACHELINE;

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());  
  if (corenum() == 2) {
    test_numbers = (int*)malloc(kMaxNumbers * sizeof(int));
    for (unsigned int i = 0; i < kMaxNumbers; i++) {
      test_numbers[i] = i;
    }
  }
  msrand(2000 + corenum());
  access_test(1 << 10, 100000);
  access_test(1 << 14, 100000);
  xprintf("[%02u]: Done\n", corenum());  
}

void access_test(int dht_size, int iterations) 
{
  if (corenum() == 2) {
    xprintf("[%02u]: dht_size: %d, iterations: %d\n", 
      corenum(), dht_size, iterations);
  }

  hw_barrier();
  const unsigned int start_time = *cycleCounter;
  for (int i = 0; i < iterations; i++) {
    int k = mrand() & (dht_size - 1);
    if (test_numbers[k] != k) {
      xprintf("[%02u]: fail, test_numbers[%d] == %d\n", 
        corenum, k, test_numbers[k]);
    }
  }
  hw_barrier();
  const unsigned int end_time = *cycleCounter;
  if (corenum() == 2) {
    xprintf("[%02u]: run time: %d, time per iteration: %d\n",
      corenum(), end_time - start_time, (end_time - start_time) / iterations);
  }
}
