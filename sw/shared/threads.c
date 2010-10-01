////////////////////////////////////////////////////////////////////////////
//                                                                        //
// threads.c                                                              //
//                                                                        //
// Threads, Semaphores, Mutexes, etc.                                     //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include "threads.h"

// #define assert(b, s) if (!(b)) { printf("Bug: %s\n", (s)); abort(); }
#define assert(b, s)
// Using "assert" slows the performance of context switch significantly


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Concrete types for public reference types                              //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

typedef long long int Cycles;
// 64-bit cycle counter values for the timer machinery

struct Thread {
  void * sp;               // saved SP when not running
  Queue q;                 // thread queue this is on, or NULL
  Thread next;             // thread queue link
  Thread tqNext;           // timer queue link
  Thread tqPrev;           // timer queue back-pointer
  Cycles tqWakeup;         // value of "now" when timer expires; 0 if none
  int timedOut;            // true iff woken up by a timeout
  void (* forkee)(void *); // target of "fork" call
  void * forkArg;          // argument to be passed to forkee
  int id;                  // unique ID assigned by "fork"
  void * stackBase;        // allocated stack (NULL for initial thread)
  void * stackTop;         // top of stack; the thread's initial SP
  int status;              // result status from thread_exit, default 0
  int detached;            // true iff nobody will ever join this thread
  Semaphore joiner;        // block here in Join until thread terminates
};

struct Semaphore {
  struct Queue q;
  int count;
};

struct Mutex {
  struct Queue q;
  int unlocked;
};

struct Condition {
  struct Queue q;
};


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Assembly code function prototypes, implemented in xfer.as              //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

void k_resume(void * dest);
void k_startThread(void ** srce, void * dest);
void k_xfer(void ** srce, void * dest);


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Globals and initialization                                             //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

static volatile unsigned int *cycles = (unsigned int *)0x22;
// Hardware cycle counter in I/O space

static volatile unsigned int *rs232 = (unsigned int *)0x02;
// RS232 device

static unsigned int clockFrequency() {
  // Return the CPU clock frequency, in MHz
  return (*rs232 >> 18) & 127;
}

static struct Queue dead;     // Threads that have terminated, for re-use
static struct Queue ready;    // Threads ready to run
static Thread running = NULL; // Currently executing thread
static struct Queue tq;       // Queue of threads waiting for timed wakeup
static int forkCount = 0;     // UID generator for forked threads
static int xferCount = 0;     // performance counter
static unsigned int prevCycles; // last cycle counter seen by timer stuff
static Cycles now = 1;        // inferred high precision cycle counter

static void thread_init() {
  // Initialize our globals, if needed.  Idempotent.
  // Called implicitly from the top-level entry points.
  if (running == NULL) {
    Thread target = malloc(sizeof(struct Thread));
    running = target; // prevent recursive calls of "init"
    queue_init(&dead);
    queue_init(&ready);
    queue_init(&tq);
    prevCycles = *cycles;
    now = 1; // "0" in tqWakeup means not on tq.
    target->next = NULL;
    target->tqNext = NULL;
    target->tqPrev = NULL;
    target->tqWakeup = 0;
    target->joiner = sem_create();
    // Don't need stackBase, stackTop, forkee, forkArg
    target->id = 0;
    target->status = 0;
    target->detached = 0;
  }
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Thread Queues and timers                                               //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

static inline void enqueue(Queue q, Thread t) {
  // Private: append given thread to given queue
  assert(q, "Enqueue on null");
  assert(!t->q, "Double enqueue");
  if (q->head) {
    assert(q->tail, "mangled queue tail");
    q->tail->next = t;
  } else {
    q->head = t;
  }
  q->tail = t;
  t->q = q;
}

static void dequeueOne(Thread t) {
  // Private: remove T from whatever queue it is on.
  // Use only for timeout wakeups.
  assert(t->q, "Improper dequeue");
  Thread this = t->q->head;
  Thread prev = NULL;
  while (this != t) {
    assert(this, "Not on queue");
    prev = this;
    this = this->next;
  }
  if (prev) {
    prev->next = this->next;
  } else {
    t->q->head = this->next;
  }
  this->q = NULL;
  this->next = NULL;
}

static Thread dequeue(Queue q) {
  // Private: remove head element from given queue
  assert(q, "Dequeue from null");
  assert(q->head, "Empty queue");
  Thread res = q->head;
  q->head = res->next;
  res->q = NULL;
  res->next = NULL;
  return res;
}

void queue_init(Queue q) {
  // Public: initialize q to be empty
  thread_init();
  q->head = NULL;
  q->tail = NULL;
}

int queue_isEmpty(Queue q) {
  // Public: is q empty?
  return (!(q->head));
}

static void readClock() {
  // Update "now" based on change in the cycle counter.
  //
  // This must be called often enough to avoid having the hardware cycle
  // counter wrap without us noticing.  For example, at least once every
  // 20 seconds at 100 MHz.  This happens in tqEnqueue and checkTimeout,
  // and therefore from every scheduling operation and thread_yield.
  //
  unsigned int c = *cycles;
  now += c - prevCycles;
  prevCycles = c;
}

static void tqEnqueue(Thread t, Microsecs microsecs) {
  // Private: place t on the timer queue
  assert(!t->tqWakeup, "Double tq enqueue");
  readClock();
  t->tqWakeup = now + clockFrequency() * microsecs;
  if (tq.head) {
    assert(tq.tail, "mangled tq queue tail");
    t->tqPrev = tq.tail;
    tq.tail->tqNext = t;
  } else {
    tq.head = t;
  }
  tq.tail = t;
}

static void tqDequeue(Thread t) {
  // Private: remove t from the timer queue
  assert(t->tqWakeup, "Improper tq dequeue");
  if (t == tq.head) tq.head = t->tqNext;
  if (t == tq.tail) tq.tail = t->tqPrev;
  if (t->tqPrev) t->tqPrev->tqNext = t->tqNext;
  if (t->tqNext) t->tqNext->tqPrev = t->tqPrev;
  t->tqNext = NULL;
  t->tqPrev = NULL;
  t->tqWakeup = 0;
}

static void checkTimeout() {
  // Private: check for a timed-out thread.
  Thread this = tq.head;
  readClock();
  while (this) {
    if (this->tqWakeup <= now) {
      assert(this->q, "Timeout target not on a queue");
      dequeueOne(this);
      tqDequeue(this);
      this->timedOut = 1;
      enqueue(&ready, this);
    }
    this = this->tqNext;
  }
}


static void schedule() {
  // Private: spin until there's a ready thread, and make it running
  while (queue_isEmpty(&ready)) checkTimeout();
  running = dequeue(&ready);
}

int queue_block(Queue q, Microsecs microsecs) {
  // Public: enqueue "running" on "q" and run something else.
  // Return true iff woken up by timeout
  Thread wasRunning = running;
  enqueue(q, running);
  running->timedOut = 0;
  if (microsecs > 0) tqEnqueue(running, microsecs);
  schedule();
  if (running != wasRunning) {
    xferCount++;
    k_xfer(&(wasRunning->sp), running->sp);
  }
  return running->timedOut;
}

void queue_unblock(Queue q) {
  // Public: move a thread from "q" to "ready"
  Thread t = dequeue(q);
  if (t->tqWakeup) tqDequeue(t);
  enqueue(&ready, t);
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Operations on Threads                                                  //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

Thread thread_self() {
  // Public: returns the currently executing thread
  thread_init();
  return running;
}

int thread_id(Thread t) {
  // Public: returns UID of the given thread
  return t->id;
}

extern int stacksize;
Thread thread_fork(void forkee(void *), void * forkArg) {
  // Public: create a thread executing "forkee(forkArg)"
  thread_init();
  Thread target;
  if (queue_isEmpty(&dead)) {
    // allocate a new one
    target = malloc(sizeof(*target));
    target->next = NULL;
    target->tqNext = NULL;
    target->tqPrev = NULL;
    target->tqWakeup = 0;
    target->stackBase = malloc(stacksize);
    target->stackTop = target->stackBase + stacksize;
    target->joiner = sem_create();
  } else {
    // recycle an old one
    target = dequeue(&dead);
  }
  forkCount++;
  target->id = forkCount;
  target->forkee = forkee;
  target->forkArg = forkArg;
  target->status = 0;
  target->detached = 0;
  void * saveSP = &(running->sp);
  enqueue(&ready, running);
  running = target;
  xferCount++;
  k_startThread(saveSP, target->stackTop);
  return target;
}

void thread_exit(int status) {
  // Public: terminate this thread, abandoning the call-stack.
  thread_init();
  running->status = status;
  sem_V(running->joiner);
  if (running->detached) thread_join(running);
  schedule();
  xferCount++;
  k_resume(running->sp);
}

void * k_threadBase() {
  // Private: the root of each forked thread's call stack
  // Called exclusively from k_startThread
  // Never returns
  (running->forkee)(running->forkArg);
  thread_exit(0);
}

int thread_join(Thread t) {
  // Public: block until t has terminated, then recycle it.
  assert(t->id >= 0, "Joining dead thread");
  sem_P(t->joiner);
  if (t->id > 0) {
    // Not the initial thread
    t->id = -1;
    enqueue(&dead, t);
  }
  return t->status;
}

void thread_detach(Thread t) {
  // Public: detach the thread
  t->detached = 1;
  if (t->joiner->count > 0) thread_join(t); // t has already terminated
}

void thread_yield() {
  // Public: if there's something else ready to run, run it instead
  thread_init();
  checkTimeout();
  if (!queue_isEmpty(&ready)) queue_block(&ready, 0);
}

void thread_sleep(Microsecs microsecs) {
  // Public: return after given delay, allowing other threads to run
  // meanwhile.
  struct Queue q;
  thread_init();
  queue_init(&q);
  queue_block(&q, microsecs);
}

Microsecs thread_now() {
  return now / clockFrequency();
}
  
int thread_xfers() {
  // Public: returns a count of context switches,
  // i.e. how often "running" has changed (fork, exit, queue_block)
  return xferCount;
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Semaphores                                                             //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

Semaphore sem_create() {
  Semaphore s = malloc(sizeof(*s));
  queue_init(&(s->q));
  s->count = 0;
  return s;
}

void sem_P(Semaphore s) {
  assert(s, "Null semaphore in P");
  if (s->count != 0) {
    s->count--;
  } else {
    queue_block(&(s->q), 0);
  }
}

void sem_V(Semaphore s) {
  assert(s, "Null semaphore in V");
  if (queue_isEmpty(&(s->q))) {
    s->count++;
  } else {
    queue_unblock(&(s->q));
  }
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Mutexes                                                                //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

Mutex mutex_create() {
  Mutex m = malloc(sizeof(*m));
  queue_init(&(m->q));
  m->unlocked = 1;
  return m;
}

void mutex_acquire(Mutex m) {
  assert(m, "Null mutex in acquire");
  if (m->unlocked) {
    m->unlocked = 0;
  } else {
    queue_block(&(m->q), 0);
  }
}

void mutex_release(Mutex m) {
  assert(m, "Null mutex in release");
  if (queue_isEmpty(&(m->q))) {
    m->unlocked = 1;
  } else {
    queue_unblock(&(m->q));
  }
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Condition Variables                                                    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

Condition condition_create() {
  Condition c = malloc(sizeof(*c));
  queue_init(&(c->q));
  return c;
}

int condition_timedWait(Condition c, Mutex m, Microsecs microsecs) {
  assert(c, "Null condition in timedWait");
  assert(m, "Null mutex in timedWait");
  mutex_release(m);
  int timedOut = queue_block(&(c->q), microsecs);
  mutex_acquire(m);
  return timedOut;
}

void condition_signal(Condition c) {
  assert(c, "Null condition in signal");
  if (!queue_isEmpty(&(c->q))) queue_unblock(&(c->q));
}

void condition_broadcast(Condition c) {
  assert(c, "Null condition in broadcast");
  while (!queue_isEmpty(&(c->q))) queue_unblock(&(c->q));
}
