#ifndef _BARRIER_H_
#define _BARRIER_H_

/*
 * Software barrier implemented using Shared Memory
 */
void sm_barrier(void);

/*
 * Hardware barrier
 */
void hw_barrier(void);

#endif
