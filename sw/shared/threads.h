////////////////////////////////////////////////////////////////////////////
//                                                                        //
// threads.h                                                              //
//                                                                        //
// Provides a threading facility, running on a single core                //
// non-preemptively (i.e., context switches occur only during             //
// explicit calls into this library).                                     //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#ifndef _THREADS_H
#define _THREADS_H


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Data types                                                             //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

typedef long long int Microsecs;

typedef struct Thread * Thread;
//
// This is a handle on a control block for a forked thread (or
// for the original thread).  Thread handles get recycled after
// the thread has terminated and has been joined or detached.

typedef struct Queue {
  Thread head;
  Thread tail;
} * Queue;
//
// A thread queue provides the primitive operations on which the
// synchronization facilites (Semaphore, Mutex, Condition) are
// built.  A client might also use thread queues to build other
// synchronization facilites.
//
// "struct Queue" is exposed here to allow clients to imbed it
// in other structures.  The innards of a "struct Queue" should
// be accessed only by calling the functions declared here.

typedef struct Semaphore * Semaphore;
//
// A general counting semaphore

typedef struct Mutex * Mutex;
//
// A binary mutual exclusion lock.  These locks are not thread
// re-entrant.  I.e., if a thread tries to acquire a mutex while
// that same thread is holding that mutex, it will deadlock.
// A client could quite trivially build re-entrant mutexes out of
// the thread queue operations.

typedef struct Condition * Condition;
//
// A condition variable, as in Mesa, Modula-3, or Posix Threads.


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Operations on Threads                                                  //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

Thread thread_self();
// Returns the Thread handle for the currently executing thread.

int thread_id(Thread t);
// Returns a UID for the given thread.

Thread thread_fork(void forkee(void *), void * forkArg);
// Create a thread executing "forkee(forkArg)".
//
// The forked thread calls thread_exit(0) if forkee ever returns.
//
// Might cause a context switch.

void thread_exit(int status);
// Terminate this thread, with status to be returned from thread_join.
//
// Never returns.  Can be used from the initial thread.
//
// Will cause a context switch.

int thread_join(Thread t);
// Block until t has terminated and return its status.
//
// Allowed only once per thread_fork.
// On return, the thread's resources will have been recycled, and "t"
// should no longer be used until it is once again returned from
// thread_fork.  Illegal on a detached thread.
//
// Might cause a context switch.

void thread_detach(Thread t);
// Nobody will ever call thread_join(t), so its resources can be
// recycled immediately when it terminates.

void thread_yield();
// If there's something else ready to run, run it instead.
//
// Might cause a context switch.

void thread_sleep(Microsecs microsecs);
// Suspend this thread for given number of microseconds, approximately
//
// Might cause a context switch

Microsecs thread_now();
// Elapsed microseconds since start of time
  
int thread_xfers();
// Returns a count of context switches.


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Thread Queues                                                          //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

void queue_init(Queue q);
// Initialize q to be empty.

int queue_isEmpty(Queue q);
// Return 1 if q is empty, 0 otherwise.

int queue_block(Queue q, Microsecs microsecs);
// Suspend the current thread and add it to q, then transfer to
// a ready thread.  Illegal if there is no such thread.
// Returns true iff woken up by a timeout.
//
// Thread will be removed from q and made ready to run after given delay,
// unless removed earlier by queue_unblock.
//
// Will cause a context switch.

void queue_unblock(Queue q);
// Remove one thread from q and make it ready to run.
//
// Might cause a context switch.


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Semaphores                                                             //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

Semaphore sem_create();
// Create and initialize a counting semaphore.

void sem_P(Semaphore s);
// Block until s->count > 0, then decrement it, atomically.
//
// Might cause a context switch.

void sem_V(Semaphore s);
// Increment s->count, atomically (and perhaps resume a blocked thread).
//
// Might cause a context switch.


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Mutexes                                                                //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

Mutex mutex_create();
// Create and initialize a mutex lock.

void mutex_acquire(Mutex m);
// Acquire a mutex lock, blocking until this is possible.
//
// Might cause a context switch.

void mutex_release(Mutex m);
// Release a mutex lock, allowing one blocked thread (if any)
// to run.
//
// Might cause a context switch.


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Condition Variables                                                    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

Condition condition_create();
// Create and initialize a condition variable

int condition_timedWait(Condition c, Mutex m, Microsecs microsecs);
// Wait on the condition variable, with the lock released (atomically).
// Re-acquires the lock when unblocked by signal, broadcast, or timeout.
// Returns true iff woken up by a timeout.
//
// Will cause a context switch.

static void condition_wait(Condition c, Mutex m) {
  condition_timedWait(c, m, 0);
}

void condition_signal(Condition c);
// If a thread is waiting on c, unblock it and make it ready to run.
//
// Might cause a context switch.

void condition_broadcast(Condition c);
// Unblock and make make ready all threads currently waiting on c.
//
// Might cause a context switch.

#endif
