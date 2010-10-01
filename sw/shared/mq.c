////////////////////////////////////////////////////////////////////////////
//                                                                        //
// mq.c                                                                   //
//                                                                        //
// Shared access to the inter-core message queue                          //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "intercore.h"
#include "network.h"

static Mutex mqMutex = NULL;
static MQReceiver *mqHandlers;

static void mqInit();

static void mqDiscard(unsigned int srce, unsigned int type,
          IntercoreMessage *msg, unsigned int len) {
   printf("Unexpected message: %d word(s) from %d, type %d",
     len, srce, type);
   // for (int i = 0; i < len; i++) printf(", 0x%x", (*msg)[i]);
   printf("\n");
}

static void mqReceiver(void * arg) {
  // Root message queue dispatcher, forked by "mqInit"
  for (;;) {
    IntercoreMessage msg;
    unsigned int status;
    while ((status = message_recv(&msg)) == 0) thread_yield();
    unsigned int srce = message_srce(status);
    unsigned int type = message_type(status);
    unsigned int len = message_len(status);
    MQReceiver r;
    mutex_acquire(mqMutex);
    r = mqHandlers[srce];
    mutex_release(mqMutex);
    r(srce, type, &msg, len);
    thread_yield();
  }
}

void mq_register(unsigned int core, MQReceiver receiver) {
  // Register up-call handler for messages from a core; NULL to disable
  mqInit();
  if (core < 64) {
    mutex_acquire(mqMutex);
    mqHandlers[core] = (receiver ? receiver : mqDiscard);
    mutex_release(mqMutex);
  }
}

static void mqInit() {
  // Initialize MQ globals and fork the message receiver thread
  if (!mqMutex) {
    mqMutex = mutex_create();
    mqHandlers = malloc(64 * sizeof(MQReceiver));
    for (int i = 0; i < 64; i++) mqHandlers[i] = mqDiscard;
    thread_fork(mqReceiver, NULL);
    printf("%u: mqinit\n", corenum());
  }
}
