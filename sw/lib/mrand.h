#include <stdlib.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

/* 
 * Generates pseudo random number
 */
int mrand (void);

/*
 * Set pseudo random nubmer generator seed
 */
void msrand (unsigned int s);
