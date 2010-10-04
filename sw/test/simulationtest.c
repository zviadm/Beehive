#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/msg.h"

void mc_init(void);
void mc_main(void);

void mc_init(void) 
{
  printf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());
  
  // Small Broadcast test
  if (corenum() == 2) {
    unsigned int x = 13;
    xprintf("[%02u]: bcast x: %u t: %u\n", corenum(), x, msgTypeDefault);
    hw_bcast_send(msgTypeDefault, 1, &x);
    //IntercoreMessage msg;
    //msg[0] = 13;
    //Message_send(3, msgTypeDefault, &msg, 1);
  } else {
    IntercoreMessage msg;    
    unsigned int st;
    while ((st = message_recv(&msg)) == 0) { 
      icSleep(100);
    }
    xprintf("[%02u]: rcv src: %u x: %u t: %u\n", 
      corenum(), message_srce(st), msg[0], message_type(st));
  }
}
