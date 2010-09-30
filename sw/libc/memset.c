#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------
   Convert C into an unsigned char and fill the first N characters of
   the array *DST with this value.

   Returns DST.
   ------------------------------------------------------------ */

void * memset (void * DST,int C,size_t N)
{
  int idst = (int)DST;
  int iend = idst + N;


  /*
   * Get rid of the zero byte case first.
   */
  if (idst == iend) return DST;


  /*
   * Compute a word-wide value that has four copies of the unsigned
   * byte C.
   */
  int c = (unsigned char)C;
  c |= c << 8;
  c |= c << 16;


  /*
   * Check for word-aligned and whole number of words.  If so, do it
   * quickly here and return.  Note that we know there is at least one
   * byte to copy.
   */
  if ((idst | iend) & 3 == 0) {
    /*
     * Backup idst by four bytes so that we can use preinc addressing.
     */
    idst -= 4;
    for (;;) {
      *(int *)(idst += 4) = c;
      if (idst == iend) return DST;
    }
  }
   

  /*
   * Store a byte at a time until idst is word-aligned.  But return if
   * we reach the end first.  Note that we know there is at least one
   * byte to copy.
   */
  while ((idst & 3) != 0) {
    *(char *)idst = c;
    idst += 1;
    if (idst == iend) return DST;
  }


  /*
   * Now idst is word-aligned.  Backup idst by four bytes so that we
   * can use preinc addressing.  Compute kend as the value that idst
   * will have when we need to exit the word-aligned loop (do not
   * forget to account for the backup).  At the end of the loop, move
   * idst forward by four bytes to cancel the backup.
   */
  idst -= 4;
  int kend = (iend-4) & ~3;
  while (idst != kend) {
    *(int *)(idst += 4) = c;
  }
  idst += 4;


  /*
   * Finish up any remaining bytes.
   */
  while (idst != iend) {
    *(char *)idst = c;
    idst += 1;
  }

  return DST;
}

    
