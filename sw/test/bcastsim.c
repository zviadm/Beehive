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

__noret__ void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());
  
  // Small Broadcast test
  IntercoreMessage msg;    
  unsigned int st;
  const unsigned int x = 13;
  
  if (corenum() == 2) {
    xprintf("[%02u]: bcast x: %u t: %u\n", corenum(), x, msgTypeDefault);
    hw_bcast_send(msgTypeDefault, 1, &x);
  } else {
    xprintf("[%02u]: send dest: %u x: %u t: %u\n", 
      corenum(), 2, x, msgTypeDefault);
    msg[0] = x;
    message_send(2, msgTypeDefault, &msg, 1);
  }

  // All cores just say what messages they receive
  while (1) {
    while ((st = message_recv(&msg)) == 0) { 
      icSleep(100);
    }
    xprintf("[%02u]: rcv src: %u x: %u t: %u\n", 
      corenum(), message_srce(st), msg[0], message_type(st));
  }
}
