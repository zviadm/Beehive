#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/msg.h"
#include "lib/barrier.h"

#include "12_cities.h"

#define DEBUG 0

void mc_init(void);
void mc_main(void);

void tsp_master(int best_path[], int *min);
void tsp_slave(void);

void tsp(int len, int cost, int path[], int best_path[], int *min);
int present(int e, int len, int path[]);


const unsigned int msgTypeRequestWork = msgTypeDefault + 1;
const unsigned int msgTypeWork        = msgTypeDefault + 2;
const unsigned int msgTypeNewMin      = msgTypeDefault + 3;
const unsigned int msgTypeDone        = msgTypeDefault + 4;
const unsigned int msgTypeBestPath    = msgTypeDefault + 5;

const unsigned int WorkPathSize = 4;

void mc_init(void) 
{
  xprintf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());
  hw_barrier();
  
  if (corenum() == 2) {
    xprintf("[%02u]: Starting TSP ...\n", corenum());
  }
  
  int best_path[NRTOWNS]; 
  int min = 10000;       

  hw_barrier();
  const unsigned int start_cycle = *cycleCounter;
  if (corenum() == 2) {
    tsp_master(best_path, &min);
  } else {
    tsp_slave();
  }
  hw_barrier();  
  const unsigned int end_cycle = *cycleCounter;

  if (corenum() == 2) {
    // print results
    xprintf("[%02u]: computation time (in CPU cycles): %u\n", 
      corenum(), end_cycle - start_cycle);
    xprintf("[%02u]: shortest path length is %d\n", corenum(), min);
    xprintf("[%02u]: best path found: ", corenum());
    for (unsigned int i = 0; i < NRTOWNS; i++) printf("%d ", best_path[i]);
    xprintf("\n");  
  }
}

void tsp_master(int best_path[], int *min) 
{
  // Master core code
  unsigned int best_path_core = 0;
  unsigned int cores_finished = 0;
  unsigned int st;
  IntercoreMessage msg;
  IntercoreMessage work_msg;
  
  srand(2010); // initialize with fixed random seed for repeatability
  
  // Generate a random ordering of three node paths, this helps us find
  // best path faster no matter what the best path is. Random will work better
  // then just straight forward enumaration in most cases.
  const unsigned int queue_size = (NRTOWNS - 1) * (NRTOWNS - 1) * (NRTOWNS - 1);
  int* work_queue = malloc(queue_size * sizeof(int));    
  for (unsigned int i = 0; i < queue_size; i++) work_queue[i] = i;  
  for (unsigned int i = 1; i < queue_size; i++) {
    const unsigned int k = rand() % (i - 1);
    const unsigned int tmp = work_queue[i];
    work_queue[i] = work_queue[k];
    work_queue[k] = tmp;
  }
  
  for (unsigned int i = 0; i < queue_size; i++) {
    const unsigned int t1 = work_queue[i] % (NRTOWNS - 1) + 1;
    const unsigned int t2 = (work_queue[i] / (NRTOWNS - 1)) % (NRTOWNS - 1) + 1;
    const unsigned int t3 = 
      (work_queue[i] / ((NRTOWNS - 1) * (NRTOWNS - 1))) % (NRTOWNS - 1) + 1;

    if ((t1 == t2) || (t1 == t3) || (t2 == t3)) continue;
    
    const int cost = 
      distance[0][t1] + distance[t1][t2] + distance[t2][t3];
      
    if (cost < *min) {
      // setup work message
      work_msg[0] = cost;
      work_msg[1] = t1;
      work_msg[2] = t2;
      work_msg[3] = t3;
      if (DEBUG) xprintf("[%02u]: Generated Work %u %u %u, cost %d\n",
        corenum(), t1, t2, t3, cost);
        
      while (1) {
        // wait for work request message
        while ((st = message_recv(&msg)) == 0) { }
      
        if (message_type(st) == msgTypeRequestWork) {            
          // send work to the appropriate core
          message_send(
            message_srce(st), msgTypeWork, &work_msg, WorkPathSize);
          break;
        } else if (message_type(st) == msgTypeNewMin) {
          if ((int)(msg[0]) < *min) {
            *min = msg[0];
            best_path_core = message_srce(st);
          }
          if (*min <= cost) break;                          
        } else {
          die("[%02u]: Received invalid message src: %u, type: %u\n",
            corenum(), message_srce(st), message_type(st));
        }              
      }
    }
  }
  
  if (DEBUG) xprintf("[%02u]: Distributed all the Work\n", corenum());
  while (cores_finished < nCores() - 2) {
    // wait for work request message
    while ((st = message_recv(&msg)) == 0) { }
  
    if (message_type(st) == msgTypeRequestWork) {            
      cores_finished++;
    } else if (message_type(st) == msgTypeNewMin) {
      if ((int)(msg[0]) < *min) {
        *min = msg[0];
        best_path_core = message_srce(st);
      }
    } else {
      die("[%02u]: Received invalid message src: %u, type: %u\n",
        corenum(), message_srce(st), message_type(st));
    }
  }
  
  // ask best core to send the best path
  if (DEBUG) xprintf("[%02u]: All cores are done, best core %u, min %d\n", 
    corenum(), best_path_core, *min);
    
  hw_bcast_send(msgTypeDone, 1, &best_path_core);
  while ((st = message_recv(&msg)) == 0) { }
  assert(message_type(st) == msgTypeBestPath);
  for (unsigned int i = 0; i < NRTOWNS; i++) best_path[i] = msg[i];
}

void tsp_slave() 
{
  unsigned int st;
  IntercoreMessage msg;
  IntercoreMessage best_path_msg;
  int path[NRTOWNS];
  path[0] = 0;
    
  int best_path[NRTOWNS]; // current best tour path
  int min = 10000;
  unsigned long int idle_time = 0;
  
  // Request Work Initially
  message_send(2, msgTypeRequestWork, &msg, 1);
  while (1) {
    const unsigned int start_time = *cycleCounter;
    while ((st = message_recv(&msg)) == 0) { }
    const unsigned int end_time = *cycleCounter;
    idle_time += end_time - start_time;
  
    if (message_type(st) == msgTypeWork) {            
      for (unsigned int i = 1; i < WorkPathSize; i++) path[i] = msg[i];
      tsp(WorkPathSize, msg[0], path, best_path, &min);
      // Request More Work
      message_send(2, msgTypeRequestWork, &msg, 1);
    } else if (message_type(st) == msgTypeNewMin) {
      if ((int)(msg[0]) < min) min = msg[0];
    } else if (message_type(st) == msgTypeDone) {
      if (msg[0] == corenum()) {
        for (unsigned int i = 0; i < NRTOWNS; i++) 
          best_path_msg[i] = best_path[i];
        message_send(2, msgTypeBestPath, &best_path_msg, NRTOWNS);
      }
      break;
    } else {
      die("[%02u]: Received invalid message src: %u, type: %u\n",
        corenum(), message_srce(st), message_type(st));
    }
  }
  xprintf("[%02u]: Finished, idle time %lu\n", corenum(), idle_time);
}

// recursive TSP search: look for a town to visit, path[] contains
// the len towns visited so far with a total (partial)
// tour length of cost.
void tsp(int len, int cost, int path[], int best_path[], int *min)
{
  const int me = path[len - 1];	// current end town
  IntercoreMessage msg;
  unsigned int st;
  while ((st = message_recv(&msg)) != 0) { 
    assert(message_type(st) == msgTypeNewMin);
    if ((int)(msg[0]) < *min) *min = msg[0];
  }

  if (cost >= *min) return;

  if (len == NRTOWNS) {
    const int new_cost = cost + distance[me][path[0]];
    if (new_cost < *min) {
      // new min cost tour, remember cost and path
      *min = new_cost;
      hw_bcast_send(msgTypeNewMin, 1, &new_cost);
      for (unsigned int i = 0; i < NRTOWNS; i++) best_path[i] = path[i];
    }
  } else {
    // look for next town in tour
    for (unsigned int i = 0; i < NRTOWNS; i++) {
      const int new_cost = cost + distance[me][i];
      if (!present(i, len, path) & (new_cost < *min)) {
        path[len] = i;
        tsp(len + 1, new_cost, path, best_path, min);
      }
    }
  }
}

// useful helper function:
// is virtex e present in first len entries of path?
int present(int e, int len, int path[]) 
{
  int i;

  for (i = 0; i < len; i++)
    if (path[i] == e)
      return 1;
  return 0;
}
