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
void test3_hw(void);

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
  xprintf("[%02u]: mc_init\n", corenum());  
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());  

  const unsigned int kSleepTime = 200000 * (enetCorenum() - 1);
  // Spin for kSleepTime cycles between every test, since 
  // we dont tests to interfere with each other
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
  
  icSleep(kSleepTime);
  test3_hw();
}

/*
 * Wait for nwait done messages from slaves
 */
void waitdone(unsigned nwait)
{
  IntercoreMessage msg;  

  if (DEBUG) xprintf("[%02u]: start waitdone %d\n", corenum(), nwait);
  unsigned int ndone = 0;
  while (ndone < nwait) {    
    unsigned int st;
    while ((st = message_recv(&msg)) == 0) {
      icSleep(100);
    }
    if (DEBUG) xprintf("[%02u]: received message from core %u, type %u\n", 
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

  if (DEBUG) xprintf("[%02u]: incdone\n", corenum());
  msg[0] = 1;
  message_send(2, MSG_BCAST, &msg, 1);
}

void test1(int hw, unsigned int msg_len) 
{
  if (corenum() == 2) { 
    xprintf("[%02u]: test1 start hw=%d, msg_len=%d\n", corenum(), hw, msg_len);
  }

  if (corenum() == 2) {
    if (!hw) bcast_send(MSG_BCAST, msg_len, &kTestMsg[0]);
    else hw_bcast_send(MSG_BCAST, msg_len, &kTestMsg[0]);
    waitdone(enetCorenum() - 3);
    xprintf("[%02u]: test1 passed\n", corenum());
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
  if (DEBUG) xprintf("[%02u]: received message from core %u, type %u\n", 
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
    xprintf("[%02u]: test2 start hw=%d\n", corenum(), hw);
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
    if (DEBUG) xprintf("[%02u]: received message from core %u, type %u\n", 
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
    xprintf("[%02u]: test2 passed\n", corenum());
  } else {
    incdone();
  }
}

void test3_hw()
{
  const unsigned int kIters = 1000;
  int buf[1] = {13};

  if(corenum() == 2){
    for(unsigned int i = 0; i < kIters; i++){
      hw_bcast_send(11, 1, buf);
      while(1){
        IntercoreMessage msg;
        int xst;
        while((xst = message_recv(&msg)) == 0)
          ;
        if(message_type(xst) == 12)
          break;
      }
    }
  } else if(corenum() == 3){
    for(unsigned int i = 0; i < kIters; i++){
      while(1){
        IntercoreMessage msg;
        int xst;
        while((xst = message_recv(&msg)) == 0)
          ;
        if(message_type(xst) == 11)
          break;
      }
      hw_bcast_send(12, 1, buf);
    }
  } else {
    while(1){
      IntercoreMessage msg;
      message_recv(&msg);
    }
  }
  xprintf("[%02u]: test3_hw done after %d iterations\n", corenum(), kIters);
}
