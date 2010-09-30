#ifndef BEE_H
#define BEE_H

#include <stddef.h>




/* ------------------------------------------------------------
   BEEHIVE CORE
   ------------------------------------------------------------ */

/*
 * Get my core number
 */
extern int bee_core_i(void);


/*
 * Get the number of normal cores
 */
extern int bee_core_n(void);


/*
 * Get the ethernet core number
 */
extern int bee_core_eth(void);


/*
 * Get the clock speed in MHz
 */
extern int bee_core_clock(void);




/* ------------------------------------------------------------
   BEEHIVE DCACHE
   ------------------------------------------------------------ */

/*
 * Flush the entire data cache
 */
extern void bee_dcache_flush_all(void);


/*
 * Flush and invalidate the entire data cache
 */
extern void bee_dcache_empty_all(void);


/*
 * Flush a region of memory
 *
 *   a = starting byte address
 *   n = number of bytes
 */
extern void bee_dcache_flush_rgn(void * a,size_t n);


/*
 * Flush and invalidate a region of memory
 *
 *   a = starting byte address
 *   n = number of bytes
 */
extern void bee_dcache_empty_rgn(void * a,size_t n);


/*
 * Perform dcache command.  Internal interface to hardware.
 *
 *   w = dcache command word (ROL 2)
 */
extern void bee_dcache_command_internal(int w);


/*
 * Flush a number of dcache lines.
 *
 *   f = first cache line number
 *   c = count of cache lines - 1 (range 0 .. 127)
 */
static inline void bee_dcache_flush_cachelines(unsigned int f,unsigned int c)
{
  int w = 2 | ((c & 127) << 12) | ((f & 127) << 5) | (3 << 2);
  bee_dcache_command_internal(w);
}


/*
 * Flush and invalidate a number of dcache lines.
 *
 *   f = first cache line number
 *   c = count of cache lines - 1 (range 0 .. 127)
 */
static inline void bee_dcache_empty_cachelines(unsigned int f,unsigned int c)
{
  int w = 2 | ((c & 127) << 12) | ((f & 127) << 5) | (3 << 2);
  bee_dcache_command_internal(w);
  bee_dcache_command_internal(w | (1 << 19));
}

  




/* ------------------------------------------------------------
   BEEHIVE MSG
   ------------------------------------------------------------ */

/*
 * Send a message
 *
 *   d = destination core number (1..15)
 *   t = message type (0..15)
 *   a = word aligned address of payload
 *   n = number of payload words (1..63)
 */
extern void bee_msg_send_w(int d,int t,int * a,int n);


/*
 * Poll to receive a message
 *
 *   a = word aligned address to store payload
 *
 * Result: status, 0 = no message
 */
extern int bee_msg_poll_w(int * a);


/*
 * Get receive message source core from status
 * Get receive message type from status
 * Get receive message payload word count from status
 *
 *   s = status
 */
static inline int bee_msg_status_src(int s) { return (s >> 10) & 15; }
static inline int bee_msg_status_type(int s) { return (s >> 6) & 15; }
static inline int bee_msg_status_words(int s) { return s & 63; }





/* ------------------------------------------------------------
   BEEHIVE LOCK
   ------------------------------------------------------------ */


/*
 * Attempt to acquire a lock
 *
 *   i = lock number (0..63)
 *
 * Result: zero = fail, non-zero = success
 */
extern int bee_lock_cacq(int i);


/*
 * Release a lock
 *
 *   i = lock number (0..63)
 */
extern void bee_lock_rel(int i);





#endif /* BEE_H */
