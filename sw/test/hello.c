#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"

void mc_init(void);
void mc_main(void);

void mc_init(void) 
{
  printf("corenum %u\n", corenum());
}

void mc_main(void) 
{
  xprintf("corenum %u\n", corenum());
}
