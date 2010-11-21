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

//volatile DEFINE_PER_CORE(int, start_index);
//volatile DEFINE_PER_CORE(int, partial_sum);

#define kMaxWorkerCore 7

volatile int start_index[16] CACHELINE;
volatile int partial_sum[16] CACHELINE;
volatile int partial_time[16] CACHELINE;
volatile int* numbers CACHELINE;

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());
  
  if (corenum() == 2) {
    // initialize start & done signals
    for (unsigned int i = 2; i <= nCores() + 1; i++) {
      start_index[i] = -1;
      partial_sum[i] = -1;
    }    
  }
  cache_invalidate(0, 127);
  hw_barrier();  
  
  if (corenum() == 2) {
    sum_master(0);
  } else if (corenum() <= kMaxWorkerCore) {
    sum_worker();
  }
  hw_barrier();
  
  if (corenum() == 2) {
    // initialize start & done signals
    for (unsigned int i = 2; i <= nCores() + 1; i++) {
      start_index[i] = -1;
      partial_sum[i] = -1;
    }    
  }
  cache_invalidate(0, 127);
  hw_barrier();
  
  if (corenum() == 2) {
    sum_master(1);
  } else if (corenum() <= kMaxWorkerCore) {
    sum_worker();
  }
}

void sum_master(int use_cache_push) 
{
  // generate random numbers and start workers
  const unsigned int kWorkPerCore = 64; // Size of Cache, for easier test
  numbers = (int*)malloc(kWorkPerCore * (nCores() - 2) * sizeof(int));
    
  xprintf("[%02u]: Starting SUM_MASTER cache_push: %d...\n", 
    corenum(), use_cache_push);
  
  srand(2010);
  const unsigned int time_0 = *cycleCounter;
  unsigned int nNumbers = 0;
  for (unsigned int i = 3; i <= kMaxWorkerCore; i++) {
    for (unsigned int k = 0; k < kWorkPerCore; k++) {
      numbers[nNumbers] = rand();
      nNumbers++;
    }
    
    // Do Cache Push Here
    if (use_cache_push) {
      cache_pushMem(i, 
        (void*)&numbers[(i - 3) * kWorkPerCore], 
        kWorkPerCore * sizeof(int));
    }
  }
  
  const unsigned int time_1 = *cycleCounter;
  for (unsigned int i = 3; i <= kMaxWorkerCore + 1; i++) {
    start_index[i] = (i - 3) * kWorkPerCore;
  }

  unsigned int sum = 0;
  for (unsigned int i = 3; i <= kMaxWorkerCore; i++) {
    while (partial_sum[i] == -1) { icSleep(100); }
    sum += partial_sum[i];
    partial_time[i] = *cycleCounter;
  }
  const unsigned int time_2 = *cycleCounter;

  // Check that we calculated same sum!
  unsigned int real_sum = 0;
  for (unsigned int i = 0; i < nNumbers; i++) {
    real_sum += numbers[i];
  }  
  assert(sum == real_sum);
  //free((void*)numbers);
  
  xprintf("[%02u]: Done calculating SUM: %u\n", corenum(), sum);
  xprintf("[%02u]: Setup time: %u, Computation time: %u, Total time: %u\n", 
    corenum(), time_1 - time_0, time_2 - time_1, time_2 - time_0);  
  for (unsigned int i = 3; i <= kMaxWorkerCore; i++) {
    xprintf("[%02u]: Core %02u Computation time: %u\n", 
      corenum(), i, partial_time[i] - time_1);  
  }
}

void sum_worker() 
{  
  int start;
  int end;  
  do {
    icSleep(100); // sleep for a bit then retry
    start = start_index[corenum()];
    end   = start_index[corenum() + 1];
  }while (start == -1 || end == -1);
  
  unsigned int sum = 0;
  for (int i = start; i < end; i++) sum += numbers[i];
  //xprintf("[%02u]: Calculated Partial Sum (%d -> %d): %u\n", 
  //  corenum(), start, (end - 1), sum);
  partial_sum[corenum()] = sum;
}
