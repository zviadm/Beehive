////////////////////////////////////////////////////////////////////////////
//                                                                        //
// mcMain.c                                                               //
//                                                                        //
// "main" for simple multi-core programming.                              //
//                                                                        //
// This module implements "main", called from base.o in core #1.          //
//                                                                        //
// The application should provide functions "mc_init" and "mc_main".      //
//                                                                        //
// "main" calls "mc_init", and on return from there it allocates stacks   //
// for  all the other cores, then resumes their execution at a call of    //
// "mc_main", concurrently in each core.                                  //
//                                                                        //
// Return from "mc_main" in any core just does an infinite loop there.    //
//                                                                        //
// Seel also mcLibc, for multi-core implementations of putchar, malloc    //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "intercore.h"
#include "threads.h"


// Entry points defined in the application
//
void mc_init();
void mc_main();

// Private entry point for running multi-core putchar, malloc, etc.
//
void mc_initRPC();

static void mc_exit() {
  // This is reached on return from mc_main (by "jump", not "call")
  //
  for (;;) {}
}

static void forkee(void *arg) {
  // Forked onto a full-size stack
  //
  mc_initRPC();
  int nCores = enetCorenum();
  for (int core = 2; core < nCores; core++) {
    SaveArea *save = getSaveArea(core);
    save->sp = malloc(100000) + 100000;
    save->link = (unsigned int)mc_exit;
    save->pc = (unsigned int)mc_main;
    cache_flushMem(save, sizeof(SaveArea));
  }
  mc_init();
  for (int core = 2; core < nCores; core++) {
    message_send(core, 0, NULL, 0);
  }
}

int main (int argc, const char * argv[]) {
  printf("\n[%02u]: %d cores, clock speed is %d MHz\n",
   corenum(), nCores(), clockFrequency());
  thread_fork(forkee, NULL);
  thread_exit(0);
}
