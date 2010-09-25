#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/meters.h"
#include "lib/msg.h"

#define DEBUG 0

void mc_init(void);
void mc_main(void);

void waitdone(unsigned int n);
void incdone(void);

void test1(int hw, unsigned int msg_len);
void test1_slave(unsigned int msg_len);
void test2(int hw);

// Broadcast message type
const unsigned int MSG_BCAST = 9;

// Broadcast message
const unsigned int kTestMsgMaxLen = DEBUG ? 3 : 60;
const unsigned int kTestMsg[63] = {
  2, 13, 14, 0x14a, 23, 75, 0x4a1, 7, 8, 9, 10, 11, 12,
  13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27,
  28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42,
  43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
  58, 59, 60, 61, 62
};

void mc_init(void) 
{
  xprintf("core #%u mc_init\n", corenum());  
}

void mc_main(void) 
{
  xprintf("core #%u mc_main\n", corenum());  

  const unsigned int kSleepTime = 200000 * (enetCorenum() - 1);
  // Spin for 500000 cycles (half second) between every test, since 
  // we dont have actual implementation of barrier yet and we dont want 
  // tests to interfere with each other
  for (unsigned int i = 1; i <= kTestMsgMaxLen; ++i) {
    icSleep(kSleepTime);
    test1(0, i);
  }  
  icSleep(kSleepTime);
  test2(0);
  
  for (unsigned int i = 1; i <= kTestMsgMaxLen; ++i) {
    icSleep(kSleepTime);
    test1(1, i);
  }
  icSleep(kSleepTime);
  test2(1);    
}

/*
 * Wait for nwait done messages from slaves
 */
void waitdone(unsigned nwait)
{
  IntercoreMessage msg;  

  if (DEBUG) xprintf("%u: start waitdone %d\n", corenum(), nwait);
  unsigned int ndone = 0;
  while (ndone < nwait) {    
    unsigned int st;
    while ((st = message_recv(&msg)) == 0) {
      icSleep(100);
    }
    if (DEBUG) xprintf("%u: received message from core %u, type %u\n", 
                        corenum(), message_srce(st), message_type(st));
    assert(message_srce(st) != 2);
    assert(message_type(st) == MSG_BCAST);
    assert(message_len(st) == 1);
    assert(msg[0] == 1);
    ndone += msg[0];
  }
}

/*
 * Send done message to the master
 */
void incdone()
{
  IntercoreMessage msg;

  if (DEBUG) xprintf("%u: incdone\n", corenum());
  msg[0] = 1;
  message_send(2, MSG_BCAST, &msg, 1);
}

void test1(int hw, unsigned int msg_len) 
{
  if (corenum() == 2) { 
    xprintf("test1: start hw=%d, msg_len=%d\n", hw, msg_len);
  }

  if (corenum() == 2) {
    if (!hw) bcast_send(MSG_BCAST, msg_len, &kTestMsg[0]);
    else hw_bcast_send(MSG_BCAST, msg_len, &kTestMsg[0]);
    waitdone(enetCorenum() - 3);
    xprintf("test1: passed\n");
  } else {
    test1_slave(msg_len);
  }
}

void test1_slave(unsigned int msg_len) 
{
  IntercoreMessage msg;    
  unsigned int st;
  while ((st = message_recv(&msg)) == 0) { 
    icSleep(100);
  }
  if (DEBUG) xprintf("%u: received message from core %u, type %u\n", 
                      corenum(), message_srce(st), message_type(st));
  assert(message_type(st) == MSG_BCAST);
  assert(message_len(st) == msg_len);
  for (unsigned int i = 0; i < msg_len; i++) {
    assert(msg[i] == kTestMsg[i]);
  }
  incdone();
}

void test2(int hw) 
{
  if (corenum() == 2) { 
    xprintf("test2: start hw=%d\n", hw);
  }

  IntercoreMessage msg;
  unsigned int st;  
  unsigned int broadcast_core[14] = { 0 };
  unsigned int broadcasts_received = 0;
  
  unsigned int x = 13;
  if (!hw) bcast_send(MSG_BCAST, 1, &x);
  else hw_bcast_send(MSG_BCAST, 1, &x);
  
  while (broadcasts_received < enetCorenum() - 3) {
    while ((st = message_recv(&msg)) == 0) {
      icSleep(100);
    }
    if (DEBUG) xprintf("%u: received message from core %u, type %u\n", 
                        corenum(), message_srce(st), message_type(st));  
    assert(message_type(st) == MSG_BCAST);
    assert(broadcast_core[message_srce(st)] == 0);
    
    broadcast_core[message_srce(st)] = 1;
    assert(message_len(st) == 1);
    assert(msg[0] == 13);
    broadcasts_received++;
  }
  
  if (corenum() == 2) { 
    waitdone(enetCorenum() - 3);
    xprintf("test2: passed\n");
  } else {
    incdone();
  }
}
