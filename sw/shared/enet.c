////////////////////////////////////////////////////////////////////////////
//                                                                        //
// enet.c                                                                 //
//                                                                        //
// Ethernet driver                                                        //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "intercore.h"
#include "network.h"


// NOTE: the Ethernet controller has a few peculiarites.
//   A) A transmit request can be rejected (because the controller's
//      4K transmit FIFO is full), in which case it needs to be retried.
//      This is determined only on receiving an ACK/NAK message from the
//      controller, asynchronously.  It's important to avoid problems
//      that could be caused by this message getting queued after incoming
//      "packet received" messages.  We don't suffer from this, because we
//      offload actual packet delivery to our "enetDeliver" thread.
//      We also need to know which packet has been acked, which we achieve
//      by only having one waiting for the ack at a time ("sendInProgress").
//      Usually, the ACK arrives very rapidly, so this isn't a performance
//      issue.  Having only one packet waiting for an ACK also limits how
//      much bigger enetSendBuf must be than the 4K FIFO size.
//   B) The transmit ACK/NAK doesn't imply the packet has actually been
//      transmitted, only that it will be.  The controller will still be
//      doing DMA from the packet memory, and indeed it gives us no
//      notification of when it's done.  Hence the copy into enetSendBuf,
//      and a requirement that enetSendBuf can store more data than the
//      controller's transmit FIFO size (4K bytes), and that we can't
//      recycle enetSendBuf until 4K+1500 bytes have been accepted by the
//      controller.
//   C) Even after we've told the controller to shift to new receive memory
//      the message queue can still deliver packets in the old memory,
//      limited only by the amount of memory it has left.  Hence the
//      "enetRecvBufReset" machinery.
//
// Separately, our threading machinery is non-preemptive, and incoming
// packets can queue up while the MQ receive thread isn't executing (or is
// doing other things).  The value of "enetRecvBufMargin" controls how much
// can be received during this latency.  50K bytes corresponds to 500 usec
// latency on a 1 Gb/s Ethernet delivering data continuously at full speed.
//
// Finally, using a separate "enetDeliver" thread for delivering packets by
// up-calls avoids the possibility of deadlock when a higher layer (e.g.
// TCP) has called enet_send with a lock held, and ends up blocked waiting
// for the MQ receive thread to receive its transmit ACK.


typedef struct EnetPending { // incoming packet delayed pending transmit ack
  MAC fromMAC;
  Uint16 type;
  Enet *buf;
  Uint32 len;
  int broadcast;
  struct EnetPending *next;
} *EnetPending;

static Mutex enetMutex = NULL;
static Condition enetSendCond = NULL;
static Condition enetRecvCond = NULL;
static Enet *enetFreeList = NULL;
static unsigned int enetCore = 999;
static MAC myMAC;
static int macKnown = 0;
static Thread mqThread = NULL;
static unsigned int enetSeed;       // current seed for enet_random

// Transmission
#define enetSendBufSize 8000
static Octet *enetSendBuf;
static unsigned int enetSendPos;    // next free position in enetSendBuf
static int sendInProgress;          // waiting for a transmit ack
IntercoreMessage sending;           // request message waiting transmit ack

// Reception
#define enetRecvBufSize 100000
#define enetRecvBufMargin 50000
static EnetPending pendingHead = NULL;
static EnetPending pendingTail = NULL;
static EnetReceiver* enetProtocols; // receivers, indexed by protocol
static Octet *enetRecvBuf;          // cache aligned
static int enetRecvBufReset = 0;    // told controller about new memory

MAC broadcastMAC() {
  MAC res;
  int i;
  for (i = 0; i < 6; i++) res.bytes[i] = 0xff;
  return res;
};

Enet *enet_alloc() {
  enet_init();
  mutex_acquire(enetMutex);
  if (!enetFreeList) {
    Enet *new = cacheAlign(malloc(100 * sizeof(Enet) + 31));
    for (int i = 0; i < 100; i++) {
      new->next = enetFreeList;
      enetFreeList = new;
      new++;
    }
  }
  Enet *buf = enetFreeList;
  enetFreeList = enetFreeList->next;
  buf->next = NULL;
  mutex_release(enetMutex);
  return buf;
}

void enet_free(Enet *buf) {
  enet_init();
  mutex_acquire(enetMutex);
  buf->next = enetFreeList;
  enetFreeList = buf;
  mutex_release(enetMutex);
}

MAC enet_localMAC() {
  enet_init();
  return myMAC;
}

unsigned int enet_random() {
  enet_init();
  unsigned int res;
  mutex_acquire(enetMutex);
  res = rand_r(&enetSeed);
  mutex_release(enetMutex);
  return res;
}
  
static void enetReceiveRequest() {
  // Set up a receive request for the Ethernet controller
  IntercoreMessage msg;
  msg[0] = cacheLineAddress(enetRecvBuf);
  msg[1] = cacheLineAddress(enetRecvBuf + enetRecvBufSize - 1500 - 31) |
    (1 << 31); // limit, and allow multicast
  message_send(enetCore, 0, &msg, 2);
  enetRecvBufReset = 1;
}

static void enetDiscard(MAC srce, 
                        Uint16 type, 
                        Enet *buf, 
                        Uint32 len,
                        int broadcast) {
  // printf("Unexpected enet packet type %04x\n", type);
  // Note: 0 to 0x05DC are 802.3 length fields.  We don't do 802.3
}

static void enetDeliver(void * arg) {
  // Our forked thread for deliverng packets by up-calls.
  //
  // Necessary to avoid deadlocks related to MQ thread and packet
  // transmission acks.
  for (;;) {
    mutex_acquire(enetMutex);
    while (!pendingHead) condition_wait(enetRecvCond, enetMutex);
    EnetPending this = pendingHead;
    pendingHead = pendingHead->next;
    EnetReceiver r = enetProtocols[this->type];
    mutex_release(enetMutex);
    if (r) {
      r(this->fromMAC, this->type, this->buf, 
        this->len, this->broadcast);
    }
    free(this);
  }
}

static void enetReceiver(unsigned int srce, 
                         unsigned int type,
                         IntercoreMessage *msg, 
                         unsigned int len) {
  // Up-call when a MQ message is received from the Ethernet controller
  //
  // Note that calling enet_send from this thread can deadlock (which we
  // detect).
  //
  mutex_acquire(enetMutex);
  if (!mqThread) mqThread = thread_self();
  if (len == 1) {
    // Transmit ack
    if ((*msg)[0] == 0) {
      printf("Send failed\n");
      message_send(enetCore, 0, &sending, 4);
    } else {
      sendInProgress = 0;
      condition_signal(enetSendCond);
    }
  } else if (len == 2) {
    // MAC response
    myMAC.bytes[0] = (*msg)[0] >> 24;
    myMAC.bytes[1] = ((*msg)[0] >> 16) & 255;
    myMAC.bytes[2] = ((*msg)[0] >> 8) & 255;
    myMAC.bytes[3] = (*msg)[0] & 255;
    myMAC.bytes[4] = ((*msg)[1] >> 8) & 255;
    myMAC.bytes[5] = (*msg)[1] & 255;
    macKnown = 1;
    condition_signal(enetSendCond);
  } else if (len == 4) {
    // Receive complete
    enetSeed += *cycleCounter;
    EnetPending recvdPkt = malloc(sizeof(struct EnetPending));
    // TEMP: should avoid the malloc in the common case
    recvdPkt->fromMAC.bytes[0] = ((*msg)[1] >> 8) & 255;
    recvdPkt->fromMAC.bytes[1] = (*msg)[1] & 255;
    recvdPkt->fromMAC.bytes[2] = ((*msg)[2] >> 24) & 255;
    recvdPkt->fromMAC.bytes[3] = ((*msg)[2] >> 16) & 255;
    recvdPkt->fromMAC.bytes[4] = ((*msg)[2] >> 8) & 255;
    recvdPkt->fromMAC.bytes[5] = (*msg)[2] & 255;
    recvdPkt->type = (*msg)[1] >> 16;
    recvdPkt->buf = (Enet *)((*msg)[3] << 5);
    recvdPkt->len = (*msg)[0];
    recvdPkt->broadcast = (*msg)[3] >> 31;
    recvdPkt->next = NULL;
    if ((Octet *)recvdPkt->buf == enetRecvBuf) {
      enetRecvBufReset = 0;
      cache_invalidateMem(enetRecvBuf, enetRecvBufSize);
      // The invalidate is more efficient done all at once, since
      // enetRecvBuf is much larger than the data cache.
    }
    if ((unsigned int)(recvdPkt->buf) + recvdPkt->len - 
        (unsigned int)enetRecvBuf > enetRecvBufSize - enetRecvBufMargin 
        && !enetRecvBufReset) {
      enetReceiveRequest();
    }
    if (pendingHead) {
      pendingTail->next = recvdPkt;
    } else {
      pendingHead = recvdPkt;
    }
    pendingTail = recvdPkt;
    condition_signal(enetRecvCond);
  } else {
    printf("Unexpected Enet message length %d\n", len);
  }
  mutex_release(enetMutex);
}

void enet_register(Uint16 protocol, EnetReceiver receiver) {
// Register up-call handler for an Ethernet protocol; NULL to disable
  enet_init();
  mutex_acquire(enetMutex);
  enetProtocols[protocol] = (receiver ? receiver : enetDiscard);
  mutex_release(enetMutex);
}

void enet_send(MAC dest, Uint16 type, Enet *buf, Uint32 len) {
  // Send a raw Ethernet packet
  //
  if (len < 60) len = 60;
  enet_init();
  Octet *mySendBuf;
  mutex_acquire(enetMutex);
  while (sendInProgress) {
    if (thread_self() == mqThread) {
      printf("Blocking enet_send from MQ thread.  Deadlock\n");
    }
    condition_wait(enetSendCond, enetMutex);
  }
  sendInProgress = 1;
  mySendBuf = &(enetSendBuf[enetSendPos]);
  enetSendPos = cacheMultiple(enetSendPos + len);
  if (enetSendPos + sizeof(Enet) > enetSendBufSize) enetSendPos = 0;
  mutex_release(enetMutex);
  bcopy(buf, mySendBuf, len);
  cache_flushMem(mySendBuf, len);
  sending[0] = cacheLineAddress(mySendBuf);
  sending[1] = (2 << 19) | (corenum() << 15) | (len << 4) | 1;
  sending[2] = (dest.bytes[0] << 24) | (dest.bytes[1] << 16) |
    (dest.bytes[2] << 8) | dest.bytes[3];
  sending[3] = (dest.bytes[4] << 24) | (dest.bytes[5] << 16) |
    (type & 65535);
  message_send(enetCore, 0, &sending, 4);
}

void enet_init() {
  // Initialize Enet globals, register with MQ, and obtain MAC address
  if (!enetMutex) {
    enetMutex = mutex_create();
    enetSendCond = condition_create();
    enetRecvCond = condition_create();
    mutex_acquire(enetMutex);
    enetFreeList = NULL;
    enetSeed = *cycleCounter;
    enetCore = enetCorenum();
    enetProtocols = malloc(65536 * sizeof(EnetReceiver));
    for (int i = 0; i < 65535; i++) enetProtocols[i] = enetDiscard;
    mq_register(enetCore, enetReceiver);
    enetSendBuf = cacheAlign(malloc(enetSendBufSize + 31));
    enetSendPos = 0;
    sendInProgress = 0;
    pendingHead = NULL;
    pendingTail = NULL;
    enetRecvBuf = cacheAlign(malloc(enetRecvBufSize) + 31);
    enetReceiveRequest();
    thread_fork(enetDeliver, NULL);
    IntercoreMessage msg;
    message_send(enetCore, 0, &msg, 1);
    while (!macKnown) condition_wait(enetSendCond, enetMutex);
    mutex_release(enetMutex);
  }
}
