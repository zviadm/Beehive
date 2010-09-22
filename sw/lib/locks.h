#ifndef _LOCKS_H_
#define _LOCKS_H_

/*
 * Allocation of hardware locks.
 */
enum {
  sem_xprintf = 2,
  sem_barrier_mutex,
  sem_barrier_wait,
};

#endif
