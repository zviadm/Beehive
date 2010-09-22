#ifndef _LIB_H_
#define _LIB_H_

#define MCCOREN 14

#include "lib/attr.h"
#include "lib/locks.h"

void die(const char* errstr, ...) __noret__;

/* Generate a run-time error is 'addr' isn't cache aligned */
#define assert_mcalign(addr)                         \
  do {                                               \
    if (((unsigned int)addr) % MCPAD)                \
      die("%s:%u: %s: not mcalign %08x", __FILE__,   \
          __LINE__, __func__, addr);                 \
  } while (0)

/* Generate a compile-time error if 'e' is false. */
#define static_assert(e) ((void)sizeof(char[1 - 2 * !(e)]))

#define assert(expr)                            \
  do {                                          \
    if (!(expr)) {                              \
      die("%s:%u: assertion failed: %s",        \
        __FILE__, __LINE__, #expr);             \
    }                                           \
  } while (0)

#define MCTYPE(t)                                                 \
  union __attribute__((__packed__,  __aligned__(MCPAD))) {        \
    __typeof__(t) v;                                              \
    char __p[MCPAD + (sizeof(t) / MCPAD) * MCPAD];                \
  }

#define DEFINE_PER_CORE(type, name)          \
  MCTYPE(type) __per_core__##name[MCCOREN];
#define my(name) __per_core__##name[corenum()].v
#define per_core(name, i) __per_core__##name[i].v

#define xprintf(...)          \
  do {                        \
    icSema_P(sem_xprintf);    \
    printf(__VA_ARGS__);      \
    icSema_V(sem_xprintf);    \
  } while (0)

#endif
