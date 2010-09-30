#include <string.h>




/* This function moves LENGTH characters from the block of memory
starting at `*SRC' to the memory starting at `*DST'.  `memmove'
reproduces the characters correctly at `*DST' even if the two areas
overlap.  The function returns DST as passed. */




void * memmove(void *DST, const void *SRC, size_t LENGTH)
{
  size_t n = LENGTH;
  int isrc = (int)SRC;
  int idst = (int)DST;

  if ((unsigned int)idst <= (unsigned int)isrc) {
    // ------------------------------------------------------------
    // WORK FORWARDS
    // ------------------------------------------------------------


    if (((isrc ^ idst) & 3) == 0) {
      
      // "in" and "out" have same byte alignment.
      // Copy bytes until aligned to word bounary.
      
      while (n != 0 && (isrc & 3) != 0) {
	*(char *)idst = *(char *)isrc;
	isrc += 1;
	idst += 1;
	--n;
      }
      
      // Copy words
      
      size_t n4 = n >> 2;
      while (n4 != 0) {
	*(int *)idst = *(int *)isrc;
	isrc += 4;
	idst += 4;
	--n4;
      }
      
      // Remaining bytes
      n = n & 3;
    }
    
    // Copy bytes.
    
    while (n != 0) {
      *(char *)idst = *(char *)isrc;
      isrc += 1;
      idst += 1;
      --n;
    }
  }
  else {
    // ------------------------------------------------------------
    // WORK BACKWARDS
    // ------------------------------------------------------------

    isrc += n;
    idst += n;


    if (((isrc ^ idst) & 3) == 0) {
      
      // "in" and "out" have same byte alignment.
      // Copy bytes until aligned to word bounary.
      
      while (n != 0 && (isrc & 3) != 0) {
	isrc -= 1;
	idst -= 1;
	*(char *)idst = *(char *)isrc;
	--n;
      }
      
      // Copy words
      
      size_t n4 = n >> 2;
      while (n4 != 0) {
	isrc -= 4;
	idst -= 4;
	*(int *)idst = *(int *)isrc;
	--n4;
      }
      
      // Remaining bytes
      n = n & 3;
    }
    
    // Copy bytes.
    
    while (n != 0) {
      isrc -= 1;
      idst -= 1;
      *(char *)idst = *(char *)isrc;
      --n;
    }
  }


  return DST;
}
