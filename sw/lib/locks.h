#ifndef _LOCKS_H_
#define _LOCKS_H_

/*
 * Allocation of hardware locks.
 * Semaphores 1 - 31 are used by libraries, 
 * Semaphores 32 - 63 can be used by user software as desired.
 */
enum {
  sem_xprintf = 2,
  sem_barrier_mutex,
  sem_barrier_wait0,
  sem_barrier_wait1,
  
  sem_user = 32,
};

#endif
