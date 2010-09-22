////////////////////////////////////////////////////////////////////////////
//                                                                        //
// xfer.as                                                                //
//                                                                        //
// Contect-switch assembly code support for thread.c                      //
//                                                                        //
////////////////////////////////////////////////////////////////////////////

// Imports:
	.include "stdas.as"
	.globl	_k_threadBase
	.globl	_abort

// Exports:
	.file "xfer.as"
	.globl	_k_resume
	.globl	_k_startThread
	.globl	_k_xfer


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// saveSP (private): save processor state at SP, and store SP at *r2      //
//                                                                        //
// Entry:                                                                 //
//    SP = address immediately above save area                            //
//    r3 = address to save final SP                                       //
//    r4 = to be left unchanged                                           //
//    link = return address for this subroutine                           //
// Return:                                                                //
//    SP = bottom address of save area                                    //
//    r4 = unchanged                                                      //
//                                                                        //
////////////////////////////////////////////////////////////////////////////
saveSP:
	ld	t1,link
	aqw_sub	sp,sp,4
	ld	wq,r9
	aqw_sub	sp,sp,4
	ld	wq,r10
	aqw_sub	sp,sp,4
	ld	wq,r11
	aqw_sub	sp,sp,4
	ld	wq,r12
	aqw_sub	sp,sp,4
	ld	wq,r13
	aqw_sub	sp,sp,4
	ld	wq,r14
	aqw_sub	sp,sp,4
	ld	wq,r15
	aqw_sub	sp,sp,4
	ld	wq,r16
	aqw_sub	sp,sp,4
	ld	wq,r17
	aqw_sub	sp,sp,4
	ld	wq,r18
	aqw_sub	sp,sp,4
	ld	wq,r19
	aqw_sub	sp,sp,4
	ld	wq,r20
	aqw_sub	sp,sp,4
	ld	wq,r21
	aqw_sub	sp,sp,4
	ld	wq,r22
	aqw_sub	sp,sp,4
	ld	wq,fp
	aqw_sub	r3,r3,0
	ld	wq,sp
	j	t1


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// void k_resume(void * dest);                                            //
//                                                                        //
// Resume using processor state stored at "dest" (in r3)                  //
//                                                                        //
// Set SP from "dest",                                                    //
// then load processor state from *SP,                                    //
// then return via normal function linkage at *SP.                        //
//                                                                        //
// Calling thread is either dead, or has preserved its state via          //
// saveSP for future use by another call of k_resume.                     //
// This code itself doesn't return to its own caller.                     //
//                                                                        //
// Argument is in r3                                                      //
//                                                                        //
////////////////////////////////////////////////////////////////////////////
	.type	_k_resume, @function
_k_resume:
	ld	sp,r3
	aqr_add sp,sp,0
	ld fp,rq
	aqr_add sp,sp,4
	ld r22,rq
	aqr_add sp,sp,4
	ld r21,rq
	aqr_add sp,sp,4
	ld r20,rq
	aqr_add sp,sp,4
	ld r19,rq
	aqr_add sp,sp,4
	ld r18,rq
	aqr_add sp,sp,4
	ld r17,rq
	aqr_add sp,sp,4
	ld r16,rq
	aqr_add sp,sp,4
	ld r15,rq
	aqr_add sp,sp,4
	ld r14,rq
	aqr_add sp,sp,4
	ld r13,rq
	aqr_add sp,sp,4
	ld r12,rq
	aqr_add sp,sp,4
	ld r11,rq
	aqr_add sp,sp,4
	ld r10,rq
	aqr_add sp,sp,4
	ld r9,rq
	add	sp,sp,4
	aqr_add	sp,sp,0
	add	sp,sp,4
	j	rq
	.size	_k_resume,.-_k_resume


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// void k_startThread(void ** srce, void * dest);                         //
//                                                                        //
// Specialized context switch at start of a thread.                       //
//                                                                        //
// Saves state on stack and saves SP to *srce,                            //
// then loads new SP "dest",                                              //
// then calls k_threadBase(), which never returns.                        //
//                                                                        //
// Arguments are in r3-r4                                                 //
//                                                                        //
////////////////////////////////////////////////////////////////////////////
	.type	_k_startThread, @function
_k_startThread:
	aqw_sub	sp,sp,4
	ld	wq,link
	call saveSP
	ld	sp,r4
	long_call _k_threadBase
	long_call _abort
	.size	_k_startThread,.-_k_startThread


////////////////////////////////////////////////////////////////////////////
//                                                                        //
// void k_xfer(void ** srce, void * dest);                                //
//                                                                        //
// General-purpose context switch.                                        //
//                                                                        //
// Saves state on stack and saves SP to *srce,                            //
// then loads new SP "dest",                                              //
// then restores state from new *SP and returns on new stack.             //
//                                                                        //
// Arguments are in r3-r4                                                 //
//                                                                        //
////////////////////////////////////////////////////////////////////////////
	.type	_k_xfer, @function
_k_xfer:
	aqw_sub	sp,sp,4
	ld	wq,link
	call saveSP
	ld	r3,r4
	long_j	_k_resume
	.size	_k_xfer,.-_k_xfer

