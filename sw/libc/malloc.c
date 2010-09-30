#include <stdio.h>
#include <stdlib.h>


/* ----------------------------------------------------------------------
 * Wrappers for malloc and free.
 * ---------------------------------------------------------------------- */

extern void * malloc1 (size_t size);
extern void free1 (void * addr);

void * malloc (size_t size) { return malloc1(size); }
void free (void * addr) { free1(addr); }
