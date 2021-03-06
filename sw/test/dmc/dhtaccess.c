#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "lib/barrier.h"
#include "lib/lib.h"
#include "lib/meters.h"
#include "lib/mrand.h"
#include "lib/msg.h"
#include "shared/intercore.h"

void mc_init(void);
void mc_main(void);

void AccessTest(int dht_size, int iterations);
void AccessTestWithMessaging(int dht_size, int iterations);
unsigned int GetOwnerCore(unsigned int index, unsigned int data_per_core);

const unsigned int msgTypeRequestValue = msgTypeDefault + 1;
const unsigned int msgTypeReturnValue  = msgTypeDefault + 2;

const unsigned int kMaxNumbers = 1 << 20;
volatile int* test_numbers CACHELINE;

unsigned int done;
const unsigned int sem_done = sem_user;

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());  
  if (corenum() == 2) {
    test_numbers = (int*)malloc(kMaxNumbers * sizeof(int));
    for (unsigned int i = 0; i < kMaxNumbers; i++) {
      test_numbers[i] = i;
    }
  }
  msrand(2000 + corenum());
  
  if (corenum() == 2) 
    xprintf("[%02u]: Access Test\n\n", corenum());    
  AccessTest(1 << 10, 100000);
  AccessTest(1 << 11, 100000);
  AccessTest(1 << 12, 100000);
  AccessTest(1 << 13, 100000);
  AccessTest(1 << 14, 100000);

  if (corenum() == 2) 
    xprintf("[%02u]: Access Test with Messaging\n\n", corenum());    
  AccessTestWithMessaging(1 << 10, 100000);
  AccessTestWithMessaging(1 << 11, 100000);
  AccessTestWithMessaging(1 << 12, 100000);
  AccessTestWithMessaging(1 << 13, 100000);
  AccessTestWithMessaging(1 << 14, 100000);
  
  xprintf("[%02u]: Done\n", corenum());  
}

void AccessTest(int dht_size, int iterations) 
{
  dcache_meters_start();
  hw_barrier();
  const unsigned int start_time = *cycleCounter;
  for (int i = 0; i < iterations; i++) {
    const int k = mrand() & (dht_size - 1);
    if (test_numbers[k] != k) {
      die("[%02u]: fail, test_numbers[%d] == %d\n", 
        corenum(), k, test_numbers[k]);
    }
  }
  hw_barrier();
  const unsigned int end_time = *cycleCounter;
  dcache_meters_report();
  hw_barrier();
  if (corenum() == 2) {
    xprintf("[%02u]: dht_size: %d, iterations: %d, "
            "run time: %d, time per iteration: %d\n\n",
            corenum(), dht_size, iterations, 
            end_time - start_time, (end_time - start_time) / iterations);
  }
}

inline unsigned int GetOwnerCore(unsigned int index, unsigned int data_per_core) {
  unsigned int k = index >> 3;
  unsigned int owner_core = 0;
  if (k >= (data_per_core << 3)) {
    k -= (data_per_core << 3);
    owner_core += 8;
  }
  if (k >= (data_per_core << 2)) {
    k -= (data_per_core << 2);
    owner_core += 4;
  }
  if (k >= (data_per_core << 1)) {
    k -= (data_per_core << 1);
    owner_core += 2;
  }
  if (k >= data_per_core) owner_core += 1;
  
  if (owner_core + 2 <= nCores()) return owner_core + 2;
  else return nCores();
}

void AccessTestWithMessaging(int dht_size, int iterations) 
{
  if (corenum() == 2) {
    done = 0;
  }

  dcache_meters_start();
  hw_barrier();
  const unsigned int start_time = *cycleCounter;
  const unsigned int data_per_core = (dht_size >> 3) / (nCores() - 1);
  
  IntercoreMessage msg;
  unsigned int msg_status;
  for (int i = 0; i < iterations; i++) {
    const int k = mrand() & (dht_size - 1);
    
    // Get the value of index "k" from DHT table
    unsigned int owner_core = GetOwnerCore(k, data_per_core);
        
    int value = -1;
    if (owner_core == corenum()) {
      value = test_numbers[k];
    } else {
      message_send(owner_core, msgTypeRequestValue, (IntercoreMessage*) &k, 1);
    }
    
    // Handle All message requests and wait for "value"
    while (((msg_status = message_recv(&msg)) != 0) || (value == -1)) { 
      if (msg_status == 0) continue;
      
      if (message_type(msg_status) == msgTypeReturnValue) {
        value = msg[0];
      }else if (message_type(msg_status) == msgTypeRequestValue) {
        message_send(message_srce(msg_status), msgTypeReturnValue, 
          (IntercoreMessage*) &test_numbers[msg[0]], 1);
      }else {
        die("[%02u]: Invalid message_type: %u received\n", 
          corenum(), message_type(msg_status));
      }
    }
    
    if (value != k) {
      die("[%02u]: fail, test_numbers[%d] == %d\n", corenum(), k, value);
    }
  }
  
  icSema_P(sem_done);
  done++;
  icSema_V(sem_done);
  
  while (done < nCores() - 1) {
    while ((msg_status = message_recv(&msg)) != 0) { 
      assert(message_type(msg_status) == msgTypeRequestValue);
      message_send(message_srce(msg_status), msgTypeReturnValue, 
        (IntercoreMessage*) &test_numbers[msg[0]], 1);
    }
  }
  
  hw_barrier();
  const unsigned int end_time = *cycleCounter;
  dcache_meters_report();
  hw_barrier();
  if (corenum() == 2) {
    xprintf("[%02u]: dht_size: %d, iterations: %d, "
            "run time: %d, time per iteration: %d\n\n",
            corenum(), dht_size, iterations, 
            end_time - start_time, (end_time - start_time) / iterations);
  }  
}
