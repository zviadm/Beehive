#include <string.h>
#include <stdio.h>

#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/msg.h"

void bcast_send(unsigned int type, 
                unsigned int len, 
                const unsigned int *buf)
{
  assert(len * 4 <= sizeof(IntercoreMessage));
  IntercoreMessage* msg = (IntercoreMessage*)buf;

  for (unsigned int  i = 2; i < enetCorenum(); i++) {
    if (i == corenum()) continue;
    message_send(i, type, msg, len);
  }
}

void hw_bcast_send(unsigned int type, 
                   unsigned int len, 
                   const unsigned int *buf)
{
  assert(len * 4 <= sizeof(IntercoreMessage));
  IntercoreMessage* msg = (IntercoreMessage*)buf;
  // if src == dst, then it is treated as broadcast
  message_send(corenum(), type, msg, len); 
}
