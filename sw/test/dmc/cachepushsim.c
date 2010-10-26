#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

void mc_init(void);
void mc_main(void);

int test_numbers[1024] CACHELINE;
void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());  
  
  hw_barrier();
  if (corenum() == 2) {
    for (unsigned int i = 0; i < 16; i++) {
      test_numbers[i] = i;
    }
    cache_pushMem(3, &test_numbers, 16 * sizeof(int));
    xprintf("[%02u]: Push to core 3\n", corenum());
  }
  hw_barrier();
  if (corenum() == 3) {
    for (unsigned int i = 0; i < 16; i++) {
      if (test_numbers[i] != (int)i) 
        xprintf("[%02u]: invalid test_numbers[%u] = %d\n", 
          corenum(), i, test_numbers[i]);
    }
  }
}
