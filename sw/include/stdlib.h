#ifndef STDLIB_H
#define STDLIB_H

#include <stddef.h>


/* ------------------------------------------------------------
   STDLIB
   ------------------------------------------------------------ */

extern void abort(void);
extern void * malloc(size_t size);
extern void free(void * ptr);

#define RAND_MAX 0x7fffffff
extern int rand(void);
extern void srand(unsigned int SEED);
extern int rand_r(unsigned int *SEED);


#endif /* STDLIB_H */
