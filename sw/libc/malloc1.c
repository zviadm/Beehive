#include <stdio.h>
#include <stdlib.h>
#include <string.h>


/* ----------------------------------------------------------------------
 * Validate heap on each call.
 * ---------------------------------------------------------------------- */
#define MALLOC_VALIDATE 0



/* ----------------------------------------------------------------------
 * Extra debugging trace info.
 * ---------------------------------------------------------------------- */
#define MALLOC_TRACE 0



/* ----------------------------------------------------------------------
 * System size quantization.  All system size requests are rounded up to
 * the next non-zero multiple of SYSQUANT.  Must be a power of two.
 * ---------------------------------------------------------------------- */
#define SYSQUANT 32   /* size of a cache line */



/* ----------------------------------------------------------------------
 * Chunk magic numbers.  Used to indicate the state of a chunk.  Wierd
 * values help with catching wild addresses and memory corruption.
 * ---------------------------------------------------------------------- */
#define MAGIC_CFREE 0xfeedf00d   /* chunk is free */
#define MAGIC_INUSE 0xefeedf00   /* chunk is in use by user program */
#define MAGIC_START 0xfafeedf0   /* barrier chunk at start of memory area */
#define MAGIC_AFTER 0x1dffeeda   /* barrier chunk at end of memory area */
#define MAGIC_FRING 0x4adefeed   /* free ring header chunk */





/* ----------------------------------------------------------------------
 * Memory chunk descriptor.  Header part appears at negative offset to
 * the user program and it is not modified by a correct user program.
 * ---------------------------------------------------------------------- */
struct chunk
{
  /* header part -- invisible to user program */

  struct chunk * prevmem;    /* prev chunk by address in memory area */
  struct chunk * nextmem;    /* next chunk by address in memory area */
  int magic;                 /* magic number gives state of chunk */

  /* user data starts here when the chunk is in use */

  struct chunk * prevfree;   /* prev chunk on free ring */
  struct chunk * nextfree;   /* next chunk on free ring */
};




/* ----------------------------------------------------------------------
 * Offset from chunk address to address of user data.
 * ---------------------------------------------------------------------- */
#define USEROFFSET ((size_t)&((struct chunk *)0)->prevfree)



/* ----------------------------------------------------------------------
 * Minimum possible system size of a chunk.
 * ---------------------------------------------------------------------- */
#define SYSSIZEMIN ( (sizeof(struct chunk) + SYSQUANT - 1) & ~(SYSQUANT - 1) )





/* ----------------------------------------------------------------------
 * Description of a memory area.
 * ---------------------------------------------------------------------- */
struct memarea
{
  char * start;
  char * after;
};



/* ----------------------------------------------------------------------
 * Global state of the memory allocator.
 * ---------------------------------------------------------------------- */
static int initflag = 0;            /* flag if we have been initialized */
static struct chunk freering [1];   /* free ring header */

static int memareacnt = 0;
static struct memarea memarea [10];





/* ----------------------------------------------------------------------
 * Make a block of memory into a chunk.
 * ---------------------------------------------------------------------- */
static struct chunk *
makechunk(char * prevmem,char * start,char * nextmem,int magic)
{
  if (nextmem - start < sizeof(struct chunk)) abort();

  struct chunk * c = (void *)start;

  c->prevmem = (void *)prevmem;
  c->nextmem = (void *)nextmem;
  c->magic = magic;
  c->prevfree = 0;
  c->nextfree = 0;

  return c;
}






/* ----------------------------------------------------------------------
 * Compute the user data start address of a chunk.
 * ---------------------------------------------------------------------- */
static char * addrofc(struct chunk * c)
{
  return (char *)c + USEROFFSET;
}






/* ----------------------------------------------------------------------
 * Convert a user data address into a chunk pointer.
 * ---------------------------------------------------------------------- */
static struct chunk * cfromaddr(void * addr)
{
  struct chunk * c = (void *)((char *)addr - USEROFFSET);
  return c;
}





/* ----------------------------------------------------------------------
 * Compute the size (in user data bytes) of a chunk.
 * ---------------------------------------------------------------------- */
static size_t sizeofc(struct chunk * c)
{
  return (char *)(c->nextmem) - addrofc(c);
}






/* ----------------------------------------------------------------------
 * Compute the size (in system data bytes) of a chunk.
 * ---------------------------------------------------------------------- */
static size_t syssizeofc(struct chunk * c)
{
  return (char *)(c->nextmem) - (char *)c;
}





/* ----------------------------------------------------------------------
 * Link an in use chunk into the free ring and mark it as MAGIC_CFREE.
 * ---------------------------------------------------------------------- */
static void linkfreec(struct chunk * c)
{
  if (c->magic != MAGIC_INUSE) abort();

  struct chunk * p = freering;
  struct chunk * n = p->nextfree;

  c->nextfree = n;
  c->prevfree = p;
  c->magic = MAGIC_CFREE;

  p->nextfree = c;
  n->prevfree = c;
}



/* ----------------------------------------------------------------------
 * Unlink a free chunk from the free ring and mark it as MAGIC_INUSE.
 * ---------------------------------------------------------------------- */
static void unlinkfreec(struct chunk * c)
{
  if (c->magic != MAGIC_CFREE) abort();

  struct chunk * p = c->prevfree;
  struct chunk * n = c->nextfree;

  c->nextfree = 0;
  c->prevfree = 0;
  c->magic = MAGIC_INUSE;

  p->nextfree = n;
  n->prevfree = p;
}

/* ----------------------------------------------------------------------
 * Add a memory area to the malloc free pool.
 * ---------------------------------------------------------------------- */
static void addmemarea(char * start,char * after)
{
#if MALLOC_TRACE
  printf("addmemarea: %08x %08x\n",start,after);
#endif
  
  /* trim region to integral number of SYSQUANT */
  start = (char *)( ((size_t)start + SYSQUANT - 1) & ~(SYSQUANT - 1) );
  after = (char *)( ((size_t)after               ) & ~(SYSQUANT - 1) );

  struct memarea * m = &memarea[memareacnt++];
  m->start = start;
  m->after = after;

  char * addr0 = start;
  char * addr3 = after;

  char * addr1 = addr0 + SYSSIZEMIN;
  char * addr2 = addr3 - SYSSIZEMIN;

  if (addr0 < addr1 && addr1 < addr2 && addr2 < addr3) {
    struct chunk * cs = makechunk(0,addr0,addr1,MAGIC_START);
    struct chunk * cf = makechunk(addr0,addr1,addr2,MAGIC_INUSE);
    struct chunk * ca = makechunk(addr1,addr2,addr3,MAGIC_AFTER);
    
    linkfreec(cf);
  }
}





/* ----------------------------------------------------------------------
 * Initialize the freering and add a memory area.
 * ---------------------------------------------------------------------- */
static void initialize (void)
{
  freering->prevmem = 0;
  freering->nextmem = 0;
  freering->magic = MAGIC_FRING;
  freering->prevfree = freering;
  freering->nextfree = freering;

  extern int _data_iafter;
  char * start = (char *)(4 * (int)&_data_iafter);
  //char * after = (char *)(0xf0000000);
  char * after = *(char **)(0xffc);  //cjt: filled in by Master.s with top of memory

  addmemarea(start,after);

  initflag = 1;
}





#if MALLOC_VALIDATE
/* ----------------------------------------------------------------------
 * Dump a chunk.
 * ---------------------------------------------------------------------- */
static void dump_chunk(struct chunk * c)
{
  printf("chunk %08x:",c);
  for (int i = 0;  i < 32;  i++) {
    if ((i & 3) == 0) printf("\n   ");
    printf("%08x ",((int *)c)[i]);
  }
  printf("\n");
}
#endif





/* ----------------------------------------------------------------------
 * Validate the structure of the memory areas.
 * ---------------------------------------------------------------------- */
void malloc1_validate (void)
{
#if MALLOC_VALIDATE

  for (int i = 0;  i < memareacnt;  i++) {
    struct memarea * m = &memarea[i];

    struct chunk * p = 0;
    struct chunk * c = (void *)m->start;

    if (c->magic != MAGIC_START) {
	printf("\nmalloc_validate: start chunk %08x bad magic %08x\n",
	       c,c->magic);
	dump_chunk(c);
	abort();
    }

    for (;;) {
      switch (c->magic) {
      case MAGIC_CFREE:
      case MAGIC_INUSE:
      case MAGIC_START:
      case MAGIC_AFTER:
	break;
      default:
	printf("\nmalloc_validate: chunk %08x bad magic %08x\n",
	       c,c->magic);
	dump_chunk(c);
	abort();
      }
      
      if (c->prevmem != (void *)p) {
	printf("\nmalloc_validate: chunk %08x bad prevmem %08x != %08x\n",
	       c,c->prevmem,p);
	dump_chunk(c);
	abort();
      }

      if (c->magic == MAGIC_AFTER) break;


      char * cnm = (char *)(c->nextmem);

      if ((3 & (int)cnm) != 0) {
	printf("\nmalloc_validate: chunk %08x bad nextmem %08x\n",
	       c,cnm);
	dump_chunk(c);
	abort();
      }

      char * cnmmin = (char *)c + sizeof(struct chunk);
      if (cnm < cnmmin) {
	printf("\nmalloc_validate: chunk %08x bad nextmem %08x < %08x\n",
	       c,cnm,cnmmin);
	dump_chunk(c);
	abort();
      }


      if ((char *)c->nextmem >= m->after) {
	printf("\nmalloc_validate: chunk %08x bad nextmem %08x >= %08x\n",
	       c,c->prevmem,m->after);
	dump_chunk(c);
	abort();
      }

      p = c;
      c = c->nextmem;
    }
  }

#endif /* MALLOC_VALIDATE */
}






/* ----------------------------------------------------------------------
 * Allocate a chunk of memory of a given size.  Initialize its
 * contents to zero.
 * ---------------------------------------------------------------------- */
void * malloc1 (size_t size)
{
  if (!initflag) initialize();
  malloc1_validate();


  /*
   * Compute padded system size.
   */
  size_t syssize = USEROFFSET + size;
  if (syssize < SYSSIZEMIN)  syssize = SYSSIZEMIN;
  syssize = (syssize + SYSQUANT - 1) & ~(SYSQUANT - 1);


  /*
   * Find the smallest free chunk of at least the size we want.
   */
  struct chunk * bestc = 0;
  size_t bestcsyssize = 0;
  
  for (struct chunk * c = freering->nextfree;
       c->magic == MAGIC_CFREE;
       c = c->nextfree) {

    size_t csyssize = syssizeofc(c);

    if (csyssize >= syssize) {
      if (bestc == 0 || csyssize < bestcsyssize) {
	bestc = c;
	bestcsyssize = csyssize;
      }
    }
  }

  if (bestc == 0) return 0;


  /*
   * Unlink the found chunk from the free ring.
   */
  unlinkfreec(bestc);


  /*
   * If the found chunk can usefully be split, split it.
   */
  if (bestcsyssize >= syssize + SYSSIZEMIN) {
    struct chunk * c0 = bestc->prevmem;
    struct chunk * c3 = bestc->nextmem;

    char * addr0 = (char *)c0;
    char * addr1 = (char *)bestc;
    char * addr2 = addr1 + syssize;
    char * addr3 = (char *)c3;

    struct chunk * c1 = makechunk(addr0,addr1,addr2,MAGIC_INUSE);
    struct chunk * c2 = makechunk(addr1,addr2,addr3,MAGIC_INUSE);

    c0->nextmem = c1;
    c3->prevmem = c2;

    linkfreec(c2);

    bestc = c1;

#if MALLOC_TRACE
    printf("split %08x %08x %08x %08x\n",c0,c1,c2,c3);
#endif
    malloc1_validate();
  }


  /*
   * Initialize user data contents to zero.
   */
  void * addr = addrofc(bestc);
  //memset(addr,0,sizeofc(bestc));

  return addr;
}







/* ----------------------------------------------------------------------
 * Free a previously allocated chunk of memory.
 * ---------------------------------------------------------------------- */
void free1 (void * addr)
{
  malloc1_validate();

  struct chunk * c = cfromaddr(addr);
  linkfreec(c);


  /*
   * Compact with prevmem if possible.
   */
  struct chunk * p = c->prevmem;
  if (p->magic == MAGIC_CFREE) { 
#if MALLOC_TRACE
    printf("compact %08x %08x\n",p,c);
#endif

    unlinkfreec(c);
    struct chunk * n = c->nextmem;
    p->nextmem = n;
    n->prevmem = p;

    c = p;

    malloc1_validate();
  }


  /*
   * Compact with nextmem if possible.
   */
  p = c;
  c = c->nextmem;
  if (c->magic == MAGIC_CFREE) {
#if MALLOC_TRACE
    printf("compact %08x %08x\n",p,c);
#endif

    unlinkfreec(c);
    struct chunk * n = c->nextmem;
    p->nextmem = n;
    n->prevmem = p;

    c = p;

    malloc1_validate();
  }
}




