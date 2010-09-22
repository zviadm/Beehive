////////////////////////////////////////////////////////////////////////
//                                                                    //
// intercore.as                                                       //
//                                                                    //
// Raw inter-core hardware: messages, cache management, semaphores.   //
//                                                                    //
////////////////////////////////////////////////////////////////////////

// Imports:
  .include "stdas.as"

// Exports:
  .file "intercore.as"
  .globl  _message_send
  .globl  _message_recv
  .globl  _cache_flush
  .globl  _cache_invalidate
  .globl  _icSema_V

// Constants:
  cacheControl = 14
  msgControl = 18
  semaControl = 22


////////////////////////////////////////////////////////////////////////
//                                                                    //
// void message_send(int dest, int type,                              //
//                   IntercoreMessage *buf, int len)                  //
//                                                                    //
// Send a message to core number "dest", using "len" words at "buf".  //
//                                                                    //
// Arguments are in r3-r6                                             //
//                                                                    //
// The implementation has no uses of LINK, including long_* ops, so   //
// we don't need to preserve LINK on the stack.                       //
//                                                                    //
////////////////////////////////////////////////////////////////////////
  .type  _message_send, @function
_message_send:
  // ... first place data on wq
  ld      r7,r6      // r7 (loop variable) = msg length
x1:
  sub     r7,r7,1
  jm      x2         // bail if done copying
  aqr_ld  r5,r5
  ld      wq,rq      // copy word onto wq
  add     r5,r5,4    // next word address
  j       x1
x2:          
  // ... now assemble the address
  lsl     r4,r4,6       // r4 = type << 6
  add_lsl r4,r4,r6,4    // r4 = (r4 + len) << 4
  add_lsl r4,r4,r3,5    // r4 = (r4 + dest) << 5
  aqw_add r4,r4,msgControl  // initiate the write
  j       link
  .size  _message_send,.-_message_send

////////////////////////////////////////////////////////////////////////
//                                                                    //
// unsigned int message_recv(IntercoreMessage *buf)                   //
//                                                                    //
// Receive a message into "buf" and return its status, or 0.          //
//                                                                    //
// Argument is in r3, result goes in r1                               //
//                                                                    //
// The implementation has no uses of LINK, including long_* ops,      //
// so we don't need to preserve LINK on the stack.                    //
//                                                                    //
////////////////////////////////////////////////////////////////////////
  .type  _message_recv, @function
_message_recv:
  aqr_ld  vb,msgControl    // read the device
  ld      r1,rq            // r1 = status
  jz      link             // if status == 0 then return 0
  and     r4,r1,63         // r4 = msg length
x3:          
  // r3 is current destination address
  sub     r4,r4,1
  jm      link         // if done copying, return status
  aqw_ld  vb,r3
  ld      wq,rq        // copy word onto wq
  add     r3,r3,4      // next destination word address
  j       x3
  .size  _message_recv,.-_message_recv


////////////////////////////////////////////////////////////////////////
//                                                                    //
// void cache_flush(int line, int countMinus1)                        //
//                                                                    //
// Flush a cache line                                                 //
//                                                                    //
// Arguments are in r3-r4                                             //
//                                                                    //
// The implementation has no uses of LINK, including long_* ops,      //
// so we don't need to preserve LINK on the stack.                    //
//                                                                    //
////////////////////////////////////////////////////////////////////////
  .type  _cache_flush, @function
_cache_flush:
  lsl      r4,r4,7
  add_lsl  r4,r4,r3,5
  aqw_add  r4,r4,cacheControl
  j        link
  .size  _cache_flush,.-_cache_flush


////////////////////////////////////////////////////////////////////////
//                                                                    //
// void cache_invalidate(int line, int countMinus1)                   //
//                                                                    //
// Invalidate a cache line, flushing it first                         //
//                                                                    //
// Arguments are in r3-r4                                             //
//                                                                    //
// The implementation has no uses of LINK, including long_* ops,      //
// so we don't need to preserve LINK on the stack.                    //
//                                                                    //
////////////////////////////////////////////////////////////////////////
  .type  _cache_invalidate, @function
_cache_invalidate:
  lsl      r4,r4,7
  add_lsl  r4,r4,r3,5
  aqw_add  r4,r4,cacheControl  // flush
  lsl      r5,1,19             // "invalidate", ends up at AQ[17]
  aqw_add  r5,r4,r5            // invalidate
  j        link
  .size  _cache_invalidate,.-_cache_invalidate


////////////////////////////////////////////////////////////////////////
//                                                                    //
// void icSema_V(int n)                                               //
//                                                                    //
// Perform V on an inter-core semaphore                               //
//                                                                    //
// Argument is in r3                                                  //
//                                                                    //
// The implementation has no uses of LINK, including long_* ops,      //
// so we don't need to preserve LINK on the stack.                    //
//                                                                    //
////////////////////////////////////////////////////////////////////////
  .type  _icSema_V, @function
_icSema_V:
  lsl      r3,r3,5
  aqw_add  r3,r3,semaControl
  j        link
  .size  _icSema_V,.-_icSema_V
