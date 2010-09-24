////////////////////////////////////////////////////////////////////////////
//                                                                        //
// intercore.h                                                            //
//                                                                        //
// Raw inter-core facilities: locks, messages, cache flush/invalidate     //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#ifndef _INTERCORE_H
#define _INTERCORE_H

// Data-space addresses for the devices (and cycle counter sub-device)
static volatile unsigned int* rs232 = (unsigned int *)0x00000002;
static volatile unsigned int* cycleCounter = (unsigned int *)0x00000022;
static volatile unsigned int* multiplier = (unsigned int *)0x00000006;
static volatile unsigned int* miscIO = (unsigned int *)0x0000000a;
static volatile unsigned int* cacheControl = (unsigned int *)0x0000000e;
static volatile unsigned int* msgControl = (unsigned int *)0x00000012;
static volatile unsigned int* semaControl = (unsigned int *)0x00000016;


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Configuration                                                          //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

static unsigned int corenum() {
  // Return the number of this CPU core, counting from 1
  return (*rs232 >> 10) & 15;
}

static unsigned int enetCorenum() {
  // Return the number of the Ethernet controller core
  return (*rs232 >> 14) & 15;
}

static unsigned int clockFrequency() {
  // Return the CPU clock frequency, in MHz
  return (*rs232 >> 18) & 127;
}

static void waitRS232Out() {
  // Spin until RS232 transmission is completed
  while ((*rs232 & (1 << 9)) == 0) { }
}

static void releaseRS232() {
  // Return control of RS232 channel to the TC5
  waitRS232Out();
  *miscIO = 1;
}

////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Inter-core messaging                                                   //
//                                                                        //
// The hardware breakpoint support uses message type 0, which therefore   //
// is probably best to avoid in normal software.                          //
//                                                                        //
// This API supports receiving zero-length messages, but the hardware     //
// does not.                                                              //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

typedef unsigned int IntercoreMessage[63];

void message_send(unsigned int dest, unsigned int type,
      IntercoreMessage *buf, unsigned int len);
// Send a message to core number "dest", using "len" words at "buf".
//
// Note that message lengths are measured in words, not bytes.

unsigned int message_recv(IntercoreMessage *buf);
// If there's a message available to receive, place its body in *buf,
// and return its status word.  Otherwise return 0.

static unsigned int message_srce(unsigned int s) {
  // Given a message status word, return the source core number
  return (s >> 10) & 15;
}

static unsigned int message_type(unsigned int s) {
  // Given a message status word, return the message "type" field
  return (s >> 6) & 15;
}

static unsigned int message_len(unsigned int s) {
  // Given a message status word, return the message body length (in words)
  return s & 63;
}


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Inter-core binary semaphores                                           //
//                                                                        //
// The semaphore unit stores a per-core local bit for each semaphore.     //
// The "value" of a semaphore is 1 - SUM(local bits).                     //
// "P" blocks until the semaphore value is 1 then decrements it.          //
// "V" sets the semaphore value to 1.                                     //
// The initial value of a semaphore is 1.                                 //
//                                                                        //
// The semaphore unit can also be used to emulate other usages, which is  //
// why "tryP" distinguishes the "already held" case.                      //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

static int icSleep(unsigned int n) {
  // Spin for n cycles. Assumes n is less than 2^31.
  //
  unsigned int start = *cycleCounter;
  while (*cycleCounter - start < n) {}
}

static int icSema_tryP(int n) {
  // Perform conditional-P on inter-core semaphore n.
  //   return 0 = fail: semaphore was 0, local bit is set in another core
  //   return 1 = success: semaphore was 1 and is now 0 (set our local bit)
  //   return 2 = held: semaphore was 0, local bit already set in our core
  // For normal binary semaphore "P" semantics, use "tryP(n) != 1".
  // Assumes n is in [0..63].
  //
  int semaAddr = (int)semaControl | (n << 5);
  return *((volatile int *)semaAddr);
}

static void icSema_P(int n) {
  // Perform "P" on inter-core semaphore n, spinning if the semaphore is
  // currently 0 (because the local bit is set in some core, perhaps us).
  // Assumes n is in [0..63].
  //
  while (icSema_tryP(n) != 1) icSleep(1000);
}

void icSema_V(int n);
// Perform "V" on inter-core semaphore n, making its value 1 (all local
// bits cleared).
// Assumes n is in [0..63].


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Data cache                                                             //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#define CACHELINE __attribute__(( aligned(32) section("cacheline") ))
// This gcc directive places a global aligned at a cache line multiple
// in the section "cacheline".  Since all items in that section are
// cache line aligned, the global gets its cache line(s) all to itself.
// E.g. "int i CACHELINE = 17"

void cache_flush(unsigned int line, unsigned int countMinus1);
// For cache lines [line .. line+countMinus1], if dirty write it to memory
// then mark it as clean.
// There is no argument validation; both should be in [0..127]

void cache_invalidate(unsigned int line, unsigned int countMinus1);
// Mark cache lines [line .. line+countMinus1] as invalid.
// Flushes them first, since nothing else makes sense.
// There is no argument validation; both should be in [0..127]

static unsigned int cacheLineAddress(void *addr) {
  // Return the starting cache line address for the given data address
  return (unsigned int)addr >> 5;
}

static void * cacheAlign(void *unaligned) {
  // Return first cache-line-aligned address >= "unaligned"
  return (void *)(cacheLineAddress(unaligned + 31) << 5);
}

static unsigned int cacheMultiple(unsigned int len) {
  // Return len rounded up to a multiple of the cache line size
  return ((len + 31) >> 5) << 5;
}

static void cache_flushMem(void *addr, unsigned int len) {
  // Flush memory for addresses [addr..addr+len-1]
  if (len > 0) {
    unsigned int countMinus1 =
      cacheLineAddress(addr+len-1) - cacheLineAddress(addr);
    if (countMinus1 >= 127) {
      cache_flush(0, 127);
    } else {
      cache_flush(cacheLineAddress(addr) & 127, countMinus1);
    }
  }
  // If len <= 0, countMinus1 could be negative, so don't do that
}

static void cache_invalidateMem(void *addr, unsigned int len) {
  // Invalidate memory for addresses [addr..addr+len-1]
  if (len > 0) {
    unsigned int countMinus1 =
      cacheLineAddress(addr+len-1) - cacheLineAddress(addr);
    if (countMinus1 >= 127) {
      cache_invalidate(0, 127);
    } else {
      cache_invalidate(cacheLineAddress(addr) & 127, countMinus1);
    }
  }
  // If len <= 0, countMinus1 could be negative, so don't do that
}

////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Meters                                                                 //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

// read one of the performance meters (n in range 0 to 63).
// meters are at cache lines 0xFFFFFF8 through 0xFFFFFFF.
static unsigned int read_meter(unsigned int n) {
  n &= 0x3f;
  cache_invalidate(120 + (n >> 3),1);  // invalidate cache line holding meter

  // Remember that data addresses are cyclically rotated right 2
  // so the bottom two address bits become aq[31:30] of the
  // WORD address in the read queue.  aq[30:3] are what's sent
  // to memory controller.  So we want the bottom two bits of
  // our address to be 2'b01.
  unsigned int a = 0xFFFFFF01 + (n << 2);
  return *((volatile unsigned int *)a);
}

////////////////////////////////////////////////////////////////////////////
//                                                                        //
// Save area used by initial bootstrap code on a breakpoint/interrupt     //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

typedef struct SaveArea {
  unsigned int rqCount;
  unsigned int r1;
  unsigned int r2;
  unsigned int r3;
  unsigned int r4;
  unsigned int r5;
  unsigned int r6;
  unsigned int r7;
  unsigned int r8;
  unsigned int r9;
  unsigned int r10;
  unsigned int r11;
  unsigned int r12;
  unsigned int r13;
  unsigned int r14;
  unsigned int r15;
  unsigned int r16;
  unsigned int r17;
  unsigned int r18;
  unsigned int r19;
  unsigned int r20;
  unsigned int r21;
  unsigned int r22;
  unsigned int fp;
  unsigned int t1;
  unsigned int t2;
  unsigned int t3;
  unsigned int pl;
  void *sp;
  unsigned int vb;
  unsigned int link;
  unsigned int pc;
  unsigned int rqValues[96];
} SaveArea;

void saveArea();
// Word address of the save area for core #1, defined in base.as

static SaveArea *getSaveArea(int n) {
  // Return pointer to save area for core #n
  //
  SaveArea *base = (SaveArea *)(((unsigned int)saveArea) << 2);
  return base + (n - 1);
}

#endif
