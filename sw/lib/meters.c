#include <string.h>
#include <stdio.h>

#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/meters.h"

// 16 Meters per each DCache Module
#define NDCACHE_METERS 16
struct {
  unsigned int meter[NDCACHE_METERS]; 
} dcache_meters[16];

const char *slot_type[] = {
  "Startup",
  "Token",
  "Address",
  "WriteData",
  "???",
  "???",
  "???",
  "Null",
  "Message",
  "PReq",
  "PFail",
  "VReq",
  "Broadcast",
  "Barrier",
  "???",
  "???"
};

void dcache_meters_start()
{
  // grab the current values from the meter system
  for (int i = 0; i < NDCACHE_METERS; i++) {
    dcache_meters[corenum()].meter[i] = cache_readMeter(i);
  }
}

void dcache_meters_report()
{
  unsigned int delta[NDCACHE_METERS];

  // compute the delta for each meter
  for (int i = 0; i < NDCACHE_METERS; i++) {
    delta[i] = cache_readMeter(i) - dcache_meters[corenum()].meter[i];
  }
  xprintf("[%02u]: DCache miss rates - "
          "Read: %u/%u (%u%%), Write %u/%u (%u%%), IMiss %u \n",
    corenum(), 
    delta[0], delta[2], delta[0] * 100 / delta[2], 
    delta[1], delta[3], delta[1] * 100 / delta[3],
    delta[4]);
}
