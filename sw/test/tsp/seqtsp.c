#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "shared/intercore.h"
#include "lib/lib.h"
#include "lib/barrier.h"

#include "12_cities.h"

void mc_init(void);
void mc_main(void);

void tsp(int len, int cost, int path[], int visited[], 
         int best_path[], int *min);
int present(int e, int len, int path[]);

void mc_init(void) 
{
  printf("[%02u]: mc_init\n", corenum());
}

void mc_main(void) 
{
  xprintf("[%02u]: mc_main\n", corenum());
  hw_barrier();
  
  if (corenum() == 2) {
    int path[NRTOWNS];     // current (partial) tour path
    int visited[NRTOWNS];  // count of tours of particular length
    int best_path[NRTOWNS];// current best tour path
    int min;               // cost of best tour path

    // initialization
    min = 10000;
    for (unsigned int i = 0; i < NRTOWNS; i++) visited[i] = 0;
    path[0] = 0; // starting town, we are finidng a cycle so just choose town 0

    printf("Starting TSP ...\n");
        
    const unsigned int start_cycle = *cycleCounter;
    tsp(1, 0, path, visited, best_path, &min); // find a min cost tour
    const unsigned int end_cycle = *cycleCounter;

    // print results
    printf("computation time (in CPU cycles): %u\n", end_cycle - start_cycle);
    printf("shortest path length is %d\n", min);
    printf("a best path found: ");
    for (unsigned int i = 0; i < NRTOWNS; i++) printf("%d ", best_path[i]);
    printf("\n");  
    
    printf("level\tvisited\n");
    for (unsigned int i = 0; i < NRTOWNS; i++) printf("%d\t%d\n",i,visited[i]);
  }
}

// recursive TSP search: look for a town to visit, path[] contains
// the len towns visited so far with a total (partial)
// tour length of cost.
void tsp(int len, int cost, int path[], int visited[], 
         int best_path[], int *min)
{
  const int me = path[len - 1];	// current end town
  // remember how many times we saw a tour of this length
  visited[len - 1]++;

  if (len == NRTOWNS) {
    const int new_cost = cost + distance[me][path[0]];
    if (new_cost < *min) {
      // new min cost tour, remember cost and path
      *min = new_cost;
      for (unsigned int i = 0; i < NRTOWNS; i++) best_path[i] = path[i];
    }
  } else {
    // look for next town in tour
    for (unsigned int i = 0; i < NRTOWNS; i++) {
      const int new_cost = cost + distance[me][i];
      if (!present(i, len, path) & (new_cost < *min)) {
        path[len] = i;
        tsp(len + 1, new_cost, path, visited, best_path, min);
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
