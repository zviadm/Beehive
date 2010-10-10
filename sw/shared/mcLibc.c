////////////////////////////////////////////////////////////////////////////
//                                                                        //
// mcLib.c                                                                //
//                                                                        //
// This module provides other cores with access to putchar on the RS232   //
// line, and "malloc" and "free", by inter-core messaging to core #1.     //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "shared/network.h"
#include "lib/msg.h"

//
// Primitive RPC from core != 1 to core 1
//

// Message identifiers
//
#define mcPutchar 1
#define mcMalloc 2
#define mcFree 3

// The "responseArea" data structure is used to have cores spin waiting for
// a response to a message that they sent to core #1.  We don't use an
// inter-core message for this, to avoid interfering with applications'
// use of the message system.
//
// We assume that either the core is running non-preemptively, or the caller
// is synchronizing appropriately.

int **responseAreas CACHELINE;
// Contains one int* for each core, in separate cache lines

static void clearResponse() {
  // Clear the response value for this core
  int *myResponse = responseAreas[corenum()];
  *myResponse = -1;
  cache_flushMem(myResponse, sizeof(int));
}

static int getResponse() {
  // Spin until we have a response, and return it
  //
  int *myResponse = responseAreas[corenum()];
  int res;
  for (;;) {
    cache_invalidateMem(myResponse, sizeof(int));
    res = *myResponse;
    if (res != -1) break;
    icSleep(1000);
  }
  return res;
}

static void setResponse(int core, int n) {
  // Set the response value for "core" to be "n" (n != 1)
  int *hisResponse = responseAreas[core];
  *hisResponse = n;
  cache_flushMem(hisResponse, sizeof(int));
}

static void rpcServer(unsigned int core, unsigned int type,
    MQMessage *msg, unsigned int len) {
  // Handler for messages at core #1
  if (type == msgTypeRPC) {
    int id = (*msg)[0];
    switch (id) {
    case mcPutchar:
      putchar((*msg)[1]);
      setResponse(core, 0);
      break;
    case mcMalloc: {
      size_t size = (*msg)[1];
      void *res = malloc(size);
      if (res) cache_flushMem(res, size);
      setResponse(core, (unsigned int)(res));
      break;
    }
    case mcFree:
      free((void *)((*msg)[1]));
      setResponse(core, 0);
      break;
    }
  }
}

void mc_initRPC() {
  int nCores = enetCorenum();
  responseAreas = malloc(nCores * sizeof(int *));
  cache_flushMem(&responseAreas, sizeof(int **));
  for (int core = 2; core < nCores; core++) {
    responseAreas[core] = malloc(sizeof(int));
    mq_register(core, rpcServer);
  }
  cache_flushMem(responseAreas, nCores * sizeof(int *));
}


//
// Multi-core putchar and malloc
//

int putchar(int c) {
  // Multi-core replacement for putchar: send characters to core #1
  //
  if (corenum() == 1) {
    if (c == '\n') putchar('\r');
    while ((*rs232 & 0x200) == 0) thread_yield();
    *rs232 = (c & 0xff) | 0x200;
  } else {
    clearResponse();
    IntercoreMessage msg;
    msg[0] = mcPutchar;
    msg[1] = c;
    message_send(1, msgTypeRPC, &msg, 2);
    getResponse(); // block to avoid overflowing core #1's message queue
  }
  return 0;
}

// Private entry points to libc
//
void *malloc1(size_t size);
void free1(void *ptr);

void *malloc(size_t size) {
  if (corenum() == 1) {
    return (void *) ((int) malloc1(5*4 + size) + 5*4);
  } else {
    clearResponse();
    IntercoreMessage msg;
    msg[0] = mcMalloc;
    msg[1] = size;
    message_send(1, msgTypeRPC, &msg, 2);
    void *res = (void *)getResponse();
    if (res) cache_invalidateMem(res, size);
    return res;
  }
}

void free(void *ptr) {
  if (corenum() == 1) {
    free1(ptr);
  } else {
    clearResponse();
    IntercoreMessage msg;
    msg[0] = mcFree;
    msg[1] = (unsigned int)ptr;
    message_send(1, msgTypeRPC, &msg, 2);
    getResponse();
  }
}
