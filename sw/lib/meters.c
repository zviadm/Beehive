#include <string.h>
#include <stdio.h>

#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/meters.h"

#define NMETERS 64
int meters[NMETERS];

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

// grab the current values from the meter system
void meters_start()
{
  int i;
  for (i = 0; i < NMETERS; i++)
    meters[i] = read_meter(i);
}

// report on changes in meter values since the
// call to meters_start()
void meters_report()
{
  int i;
  int delta[NMETERS];

  // compute the delta for each meter
  for (i = 0; i < NMETERS; i++)
    delta[i] = read_meter(i) - meters[i];

  xprintf("\n**** METERING REPORT ****\n");

  // print out the number of ring slots of each type
  xprintf("Count of ring slots by type:\n");
  for (i = 0; i < 16; i++) {
    if (i == 2) {
      // Address slots are counted by core and type;
      int sum = 0;  // add together all Address counts
      int j;
      for (j = 16; j < 64; j++) sum += delta[j];
      xprintf("  %d ring slots of type \"Address\"\n", sum);
    }
    else if (delta[i] > 0)
      xprintf("  %d ring slots of type \"%s\"\n",
              delta[i], slot_type[i]);
  }

  // for each core, print out number of memory requests
  xprintf("\nCount of Address slots by core:\n");
  for (i = 1; i < 16; i++)   // there is no core 0...
    xprintf("  core %2d: I=%d, Dwrite=%d, Dread=%d\n",
            i, delta[i+16], delta[i+32], delta[i+48]);
}
