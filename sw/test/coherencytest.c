#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

void mc_init(void);
void mc_main(void);

#define DEBUG 0

const unsigned int TEST_1_ITERATIONS       = 1000;
const unsigned int TEST_2_ITERATIONS       = 50;
const unsigned int TEST_3_ITERATIONS       = 1000;
const unsigned int TEST_4_ITERATIONS       = 100000;

// some test variables
volatile int done_val[16];
int test_val[16];
CACHELINE union {
  int val;
  char pad[32];
} aligned_test_val[16];

CACHELINE volatile int* mem_block;

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());  
  hw_barrier();
      
  // Simple Coherency Test 1
  if (corenum() == 2) {
    xprintf("[%02u]: test 1, iterations: %u\n", corenum(), TEST_1_ITERATIONS);  
  }
  for (unsigned int iter = 0; iter < TEST_1_ITERATIONS; iter++) {
    if (corenum() == 2) {
      for (unsigned int i = 2; i <= nCores(); i++) {
        done_val[i] = 0;             // reset dones
        test_val[i] = *cycleCounter; // a random value
      }
    }
    hw_barrier();
    if (corenum() == 2) {
      test_val[2] = 1;
      done_val[2] = 1;
    }else {
      while (done_val[corenum() - 1] == 0) { };
      test_val[corenum()] = 1;
      for (unsigned int i = 2; i < corenum(); i++) {
        test_val[corenum()] += test_val[i];
      }
      // vals in cores should be: 
      // 1, 1 + 1 = 2, 1 + 1 + 2 = 4, 1 + 1 + 2 + 4 = 8, ...
      assert(test_val[corenum()] == (1 << (corenum() - 2)));
      done_val[corenum()] = 1;
    }
    hw_barrier();
  }
  if (corenum() == 2) {
    xprintf("[%02u]: test 1 PASSED\n", corenum());  
  }
  hw_barrier();
  
  // Simple Coherency Test 2
  if (corenum() == 2) {
    xprintf("[%02u]: test 2 (takes little longer), iterations: %u\n", 
      corenum(), TEST_2_ITERATIONS);  
  }
  for (unsigned int iter = 0; iter < TEST_2_ITERATIONS; iter++) {
    test_val[corenum()] = corenum();
    for (unsigned int i = 0; i < 3000; i++) {
      test_val[corenum()]++;
    }
    hw_barrier();
    // check test_val-s
    for (unsigned int i = corenum(); i <= nCores(); i++) {
      assert(test_val[i] == (int)(i + 3000));
    }
    hw_barrier();
  }
  if (corenum() == 2) {
    xprintf("[%02u]: test 2 PASSED\n", corenum());  
  }
  hw_barrier();

  // Simple Coherency Test 3
  if (corenum() == 2) {
    xprintf("[%02u]: test 3, iterations: %u\n", corenum(), TEST_3_ITERATIONS);  
  }
  for (unsigned int iter = 0; iter < TEST_3_ITERATIONS; iter++) {
    aligned_test_val[corenum()].val = corenum();
    for (unsigned int i = 0; i < 3000; i++) {
      aligned_test_val[corenum()].val++;
    }
    hw_barrier();
    // check test_val-s
    for (unsigned int i = 2; i <= nCores(); i++) {
      assert(aligned_test_val[i].val == (int)(i + 3000));
    }
    hw_barrier();
  }
  if (corenum() == 2) {
    xprintf("[%02u]: test 3 PASSED\n", corenum());  
  }
  hw_barrier();
  
  // Test L2 cache simulation
  if (corenum() == 2) {
    xprintf("[%02u]: Testing L2 cache simulation for single core\n", corenum());
  }
  
  int start = 0, stop = 0;  
  if (corenum() == 2) {
    // L2 size is 2^16 * 32 = 64 * 1024 * 32 bytes
    mem_block = (int*)malloc(2 * 64 * 1024 * 8); 
    mem_block = (int*)cacheAlign((void*)mem_block);
    
    start = *cycleCounter;
    for (unsigned int i = 0; i < TEST_4_ITERATIONS; i++) {
      mem_block[0] = i;
      mem_block[1] = i;
    }
    unsigned int k = mem_block[0] + mem_block[1] + 
                     mem_block[128 * 8] + mem_block[64 * 1024 * 8];
    stop = *cycleCounter;
    xprintf("[%02u]: %u L1 hits: %d cycles, verify(%u)\n", 
      corenum(), TEST_4_ITERATIONS, stop - start, k);
    
    start = *cycleCounter;
    for (unsigned int i = 0; i < TEST_4_ITERATIONS; i++) {
      mem_block[0] = i;
      mem_block[128 * 8] = i;
    }
    k = mem_block[0] + mem_block[1] + 
        mem_block[128 * 8] + mem_block[64 * 1024 * 8];
    stop = *cycleCounter;
    xprintf("[%02u]: %u L2 hits: %d cycles, verify(%u)\n", 
      corenum(), TEST_4_ITERATIONS, stop - start, k);
    
    start = *cycleCounter;
    for (unsigned int i = 0; i < TEST_4_ITERATIONS; i++) {
      mem_block[0] = i;
      mem_block[64 * 1024 * 8] = i;
    }
    k = mem_block[0] + mem_block[1] + 
        mem_block[128 * 8] + mem_block[64 * 1024 * 8];
    stop = *cycleCounter;
    xprintf("[%02u]: %u L2 miss: %d cycles, verify(%u)\n", 
      corenum(), TEST_4_ITERATIONS, stop - start, k);
  }
  
  // print cores in order
  for (unsigned int i = 2; i <= nCores(); i++) {
    if (corenum() == i) {
      xprintf("[%02u]: all tests done \n", corenum());  
    }
    hw_barrier();
  }
}
