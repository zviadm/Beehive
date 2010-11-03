#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

void mc_init(void);
void mc_main(void);

void sum_master(int use_cache_push);
void sum_worker(void);

typedef struct WorkerState_ {
  int start_index;
  unsigned int partial_sum;
  unsigned int run_time;
  char padding[32 - 3 * sizeof(int)];
} WorkerState;

volatile WorkerState worker_state[16] CACHELINE;
volatile unsigned int* numbers CACHELINE;

// Size of work is fixed
const unsigned int kWorkPerCore = 512;
// Total amount of numbers to sum, should be multiple of kWorkPerCore
// and greater than nCores() * kWorkPerCore to simplify rest of the code
const unsigned int kNumbersSize = 512 * 1100;

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());
  
  if (corenum() == 2) {
    srand(2010);  
    numbers = (unsigned int*)malloc(kNumbersSize * sizeof(unsigned int));    
  }
  
  if (corenum() == 2) {
    // initialize start signals
    for (unsigned int i = 2; i <= nCores(); i++) {
      worker_state[i].start_index = -1;
      worker_state[i].partial_sum = 0;
      worker_state[i].run_time = 0;
    }
  }
  cache_invalidate(0, 127);
  hw_barrier();  
  
  if (corenum() == 2) {
    sum_master(0);
  } else {
    sum_worker();
  }
  hw_barrier();
  
  if (corenum() == 2) {
    // initialize start signals
    for (unsigned int i = 2; i <= nCores(); i++) {
      worker_state[i].start_index = -1;
      worker_state[i].partial_sum = 0;
      worker_state[i].run_time = 0;
    }
  }
  cache_invalidate(0, 127);
  hw_barrier();
  
  if (corenum() == 2) {
    sum_master(1);
  } else {
    sum_worker();
  }
}

void sum_master(int use_cache_push) 
{
  // generate random numbers and start workers      
  xprintf("\n[%02u]: Starting SUM_MASTER cache_push: %d...\n", 
    corenum(), use_cache_push);
  
  const unsigned int time_0 = *cycleCounter;  // start the timer  
  unsigned int sum = 0;       // total sum
  unsigned int nNumbers = 0;  // # of numbers already distributed
  unsigned int next_core = 3;  // next core to give numbers to
    
  while (nNumbers < kNumbersSize) {
    // prepare numbers to give to next_core
    const unsigned int next_index = nNumbers;
    for (unsigned int k = 0; k < kWorkPerCore; k++) {
      numbers[nNumbers] = nNumbers;
      nNumbers++;
    }
    
    // wait for core to finish calculating current job
    while (worker_state[next_core].start_index != -1) { icSleep(100); }
    sum += worker_state[next_core].partial_sum;
        
    if (use_cache_push) {
      // Cache push work to the worker core
      cache_pushMem(
        next_core, (void*)&numbers[next_index], kWorkPerCore * sizeof(int));
    }
    
    // start the worker core
    worker_state[next_core].start_index = next_index;                    
      
    if (next_core == nCores()) next_core = 3;
    else next_core++;
  }
  
  // wait for all cores to finish jobs and sum them up
  const unsigned int last_core = next_core;
  do {
    while (worker_state[next_core].start_index != -1) { icSleep(100); }
    sum += worker_state[next_core].partial_sum;
    worker_state[next_core].start_index = -2;
    
    if (next_core == nCores()) next_core = 3;
    else next_core++;
  } while (next_core != last_core);
  
  const unsigned int time_2 = *cycleCounter;  // end timer

  xprintf("\n[%02u]: Checking the answer: %u... \n", corenum(), sum);
  // Check that we calculated same sum!
  unsigned int real_sum = 0;
  for (unsigned int i = 0; i < nNumbers; i++) {
    real_sum += numbers[i];
  }  
  assert(sum == real_sum);
  //free((void*)numbers);
  
  xprintf("\n[%02u]: Done calculating SUM: %u\n", corenum(), sum);
  for (unsigned int i = 3; i <= nCores(); i++) {
    xprintf("[%02u]: Core %u time: %u\n", 
      corenum(), i, worker_state[next_core].run_time);
  }
  xprintf("[%02u]: Total time: %u\n", corenum(), time_2 - time_0);  
}

void sum_worker() 
{  
  while (1) {
    while (worker_state[corenum()].start_index == -1) { icSleep(100); }
    const int start = worker_state[corenum()].start_index;
    if (start == -2) break;
    
    const unsigned int time_0 = *cycleCounter;
    unsigned int sum = 0;
    for (int i = start; i < start + (int)kWorkPerCore; i++) sum += numbers[i];
    const unsigned int time_1 = *cycleCounter;
    worker_state[corenum()].run_time += time_1 - time_0;
    //xprintf("[%02u]: Calculated Partial Sum (%d -> %d): %u\n", 
    //  corenum(), start, start + (int)kWorkPerCore, sum);

    worker_state[corenum()].partial_sum = sum;
    worker_state[corenum()].start_index = -1;
  }
}
