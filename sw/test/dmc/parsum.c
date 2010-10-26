#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

void mc_init(void);
void mc_main(void);

void sum_master(void);
void sum_worker(void);

volatile int start_index[16] CACHELINE;
volatile int partial_sum[16] CACHELINE;
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
  hw_barrier();
  
  if (corenum() == 2) {
    sum_master();
  } else {
    sum_worker();
  }
}

void sum_master() 
{
  // generate random numbers and start workers
  const unsigned int kWorkPerCore = 1024; // Size of Cache, for easier test
  numbers = (int*)malloc(kWorkPerCore * (nCores() - 2) * sizeof(int));
    
  xprintf("[%02u]: Starting assigning Jobs...\n", corenum());
  const unsigned int start_time = *cycleCounter;
  
  srand(2010);
  unsigned int nNumbers = 0;
  for (unsigned int i = 3; i <= nCores(); i++) {
    start_index[i] = (i - 3) * kWorkPerCore;
    for (unsigned int k = 0; k < kWorkPerCore; k++) {
      numbers[nNumbers] = rand();
      nNumbers++;
    }
    
    // Do Cache Push Here
  }
  start_index[nCores() + 1] =  (nCores() - 2) * kWorkPerCore;
  
  xprintf("[%02u]: Done Assigning Jobs\n", corenum());

  unsigned int done = 0;
  while (done == 0) {
    done = 1;
    for (unsigned int i = 3; i <= nCores(); i++) {
      if (partial_sum[i] == -1) {
        done = 0;
        break;
      }
    }
  }
  unsigned int sum = 0;
  for (unsigned int i = 3; i <= nCores(); i++) {
    sum += partial_sum[i];
  }
  const unsigned int end_time = *cycleCounter;

  // Check that we calculated same sum!
  unsigned int real_sum = 0;
  for (unsigned int i = 0; i < nNumbers; i++) {
    real_sum += numbers[i];
  }  
  assert(sum == real_sum);
  //free(numbers);
  
  xprintf("[%02u]: Done calculating SUM: %u\n", corenum(), sum);
  xprintf("[%02u]: Computation time (in cycles): %u\n", 
    corenum(), end_time - start_time);  
}

void sum_worker() 
{  
  int start;
  int end;  
  do {
    start = start_index[corenum()];
    end   = start_index[corenum() + 1];      
  }while (start == -1 || end == -1);
  
  unsigned int sum = 0;
  for (int i = start; i < end; i++) sum += numbers[i];
  xprintf("[%02u]: Calculated Partial Sum (%d -> %d): %u\n", 
    corenum(), start, (end - 1), sum);
  partial_sum[corenum()] = sum;
}
