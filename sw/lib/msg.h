#ifndef _MSG_H_
#define _MSG_H_

/*
 * Allocation of intercore messages
 * Types 1 - 7 are used by system libraries, 
 * Types 8 - 15 can be used by software as desired.
 */
enum {
  msgTypeRPC = 1,
  /* ... */
  msgTypeDefault = 8,
};

/*
 * Software Broadcast, len is size of buffer in WORDs
 */
void bcast_send(unsigned int type, 
                unsigned int len, 
                const unsigned int *buf);

/*
 * Hardware Broadcast, len is size of buffer in WORDs
 */
void hw_bcast_send(unsigned int type, 
                   unsigned int len, 
                   const unsigned int *buf);

#endif
