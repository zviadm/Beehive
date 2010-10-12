#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

void mc_init(void);
void mc_main(void);

volatile int t[64] = { 0 };

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());  
  hw_barrier();
  
  if (corenum() == 2) {
    xprintf("[%02u]: assign t[0] = 5, t[8] = 7\n", corenum());
    t[0] = 5;
    t[8] = 7;
  }
  hw_barrier();
  
  if (corenum() == 3) {
    xprintf("[%02u]: t[0] = %d, t[8] = %d\n", corenum(), t[0], t[8]);
    xprintf("[%02u]: assign t[1] = %d + %d\n", corenum(), t[0], t[8]); 
    t[1] = t[0] + t[8];
  }
  hw_barrier();  
  
  if (corenum() == 2) {
    xprintf("[%02u]: t[0] = %d, t[8] = %d, t[1] = %d\n", 
      corenum(), t[0], t[8], t[1]);
  } 
}
