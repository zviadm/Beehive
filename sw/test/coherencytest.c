#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"

void mc_init(void);
void mc_main(void);
void barrier(void);

#define DEBUG           0
#define core_id         corenum() - 2

const unsigned int BARRIER_MUTEX = 5;

const unsigned int BARRIER_TEST_ITERATIONS = 1000;
const unsigned int TEST_1_ITERATIONS       = 1000;
const unsigned int TEST_2_ITERATIONS       = 50;
const unsigned int TEST_3_ITERATIONS       = 1000;
const unsigned int TEST_4_ITERATIONS       = 100000;

// Barrier variables
unsigned int ncores;
volatile unsigned int barrier_val_1;
volatile unsigned int barrier_val_2;

// some test variables
volatile int done_val[16];
int test_val[16];
CACHELINE union {
  int val;
  char pad[32];
} aligned_test_val[16];
char* mem_block;

void mc_init(void) 
{
  // initialize some global variables
  ncores = enetCorenum() - 2;
  barrier_val_1 = ncores;
  barrier_val_2 = ncores;
}

// Barrier implemented without messageing
void barrier(void)
{
  // Make sure everyone enters barrier
  icSema_P(BARRIER_MUTEX);
  if (barrier_val_1 == ncores) barrier_val_1 = 1;
  else barrier_val_1++;
  if (DEBUG) xprintf("[%u]: barrier_val_1 %u\n", core_id, barrier_val_1);  
  icSema_V(BARRIER_MUTEX);
  while (barrier_val_1 != ncores) { };
  
  // Make sure everyone leaves barrier
  icSema_P(BARRIER_MUTEX);
  if (barrier_val_2 == ncores) barrier_val_2 = 1;
  else barrier_val_2++;
  if (DEBUG) xprintf("[%u]: barrier_val_2 %u\n", core_id, barrier_val_2);  
  icSema_V(BARRIER_MUTEX);
  while (barrier_val_2 != ncores) { };
}

void mc_main(void) 
{
  xprintf("[%u]: starting mc_main, number of cores %u\n", core_id, ncores);  
  barrier();
    
  // Test Barriers
  if (core_id == 0) {
    xprintf("[%u]: barrier stress test 1, iterations: %u\n", core_id, BARRIER_TEST_ITERATIONS);
  }
  for (unsigned int iter = 0; iter < BARRIER_TEST_ITERATIONS; iter++) {
    barrier();
  }
  
  // Simple Coherency Test 1
  if (core_id == 0) {
    xprintf("[%u]: starting coherency test 1, iterations: %u\n", core_id, TEST_1_ITERATIONS);  
  }
  for (unsigned int iter = 0; iter < TEST_1_ITERATIONS; iter++) {
    if (core_id == 0) {
      for (unsigned int i = 0; i < ncores; i++) {
        done_val[i] = 0;             // reset dones
        test_val[i] = *cycleCounter; // a random value
      }
    }
    barrier();
    if (core_id == 0) {
      test_val[0] = 1;
      done_val[0] = 1;
    }else {
      while (done_val[core_id - 1] == 0) { };
      test_val[core_id] = 1;
      for (unsigned int i = 0; i < core_id; i++) {
        test_val[core_id] += test_val[i];
      }
      assert(test_val[core_id] == (1 << core_id));
      done_val[core_id] = 1;
    }
    barrier();
  }
  
  // Simple Coherency Test 2
  if (core_id == 0) {
    xprintf("[%u]: starting coherency test 2 (takes little longer), iterations: %u\n", core_id, TEST_2_ITERATIONS);  
  }
  for (unsigned int iter = 0; iter < TEST_2_ITERATIONS; iter++) {
    test_val[core_id] = core_id;
    for (unsigned int i = 0; i < 3000; i++) {
      test_val[core_id]++;
    }
    barrier();
    // check test_val-s
    for (unsigned int i = 0; i < ncores; i++) {
      assert(test_val[i] == (int)(i + 3000));
    }
    barrier();
  }

  // Simple Coherency Test 3
  if (core_id == 0) {
    xprintf("[%u]: starting coherency test 3, iterations: %u\n", core_id, TEST_3_ITERATIONS);  
  }
  for (unsigned int iter = 0; iter < TEST_3_ITERATIONS; iter++) {
    aligned_test_val[core_id].val = core_id;
    for (unsigned int i = 0; i < 3000; i++) {
      aligned_test_val[core_id].val++;
    }
    barrier();
    // check test_val-s
    for (unsigned int i = 0; i < ncores; i++) {
      assert(aligned_test_val[i].val == (int)(i + 3000));
    }
    barrier();
  }
  
  // Test L2 cache simulation
  if (core_id == 0) {
    xprintf("[%u]: Testing L2 cache simulation for single core\n", core_id);
  }
  
  int start = 0, stop = 0;  
  if (core_id == 0) {
    // L2 size is 2^16 * 32 = 64 * 1024 * 32 bytes
    mem_block = (char*)malloc(2 * 64 * 1024 * 32); 
    mem_block = (char*)cacheAlign((void*)mem_block);
    
    start = *cycleCounter;
    for (unsigned int i = 0; i < TEST_4_ITERATIONS; i++) {
      mem_block[0] = i;
      mem_block[1] = i;
    }
    stop = *cycleCounter;
    xprintf("[%u]: %u L1 hits: %d cycles\n", core_id, TEST_4_ITERATIONS, stop - start);
    
    start = *cycleCounter;
    for (unsigned int i = 0; i < TEST_4_ITERATIONS; i++) {
      mem_block[0] = i;
      mem_block[128 * 32] = i;
    }
    stop = *cycleCounter;
    xprintf("[%u]: %u L2 hits: %d cycles\n", core_id, TEST_4_ITERATIONS, stop - start);

    start = *cycleCounter;
    for (unsigned int i = 0; i < TEST_4_ITERATIONS; i++) {
      mem_block[0] = i;
      mem_block[64 * 1024 * 32] = i;
    }
    stop = *cycleCounter;
    xprintf("[%u]: %u L2 miss: %d cycles\n", core_id, TEST_4_ITERATIONS, stop - start);
  }
  
  // print cores in order
  for (unsigned int i = 0; i < ncores; i++) {
    if (core_id == i) {
      xprintf("[%u]: all tests done \n", core_id);  
    }
    barrier();
  }
}
