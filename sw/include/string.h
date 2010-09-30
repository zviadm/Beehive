#ifndef STRING_H
#define STRING_H

#include <stddef.h>


/* ------------------------------------------------------------
   STRING
   ------------------------------------------------------------ */

#ifdef __cplusplus
extern "C" {
#endif

extern void bzero (void *ptr,size_t n);
extern void bcopy (const void *in,void *out,size_t n);


/*
 * Prototypes of the ANSI Standard C library string functions.
 */

extern void * memchr (const void *,int,size_t);
extern int memcmp (const void *,const void *,size_t);
extern void * memcpy (void *,const void *,size_t);
extern void * memmove (void *,const void *,size_t);
extern void * memset (void *,int,size_t);

extern char * strcat (char *,const char *);
extern char * strchr (const char *,int);
extern int strcmp (const char *,const char *);
extern char * strcpy (char *dst,const char *src);
extern size_t strcspn (const char *,const char *);
extern size_t strlen (const char *str);
extern char * strncat (char *,const char *,size_t);
extern int strncmp (const char *,const char *,size_t);
extern char * strncpy (char *dst,const char *src,size_t n);
extern char * strpbrk (const char *,const char *);
extern char * strrchr (const char *,int);
extern size_t strspn (const char *,const char *);
extern char * strstr (const char *,const char *);
extern char * strtok (char *,const char *);
extern size_t strxfrm (char *,const char *,size_t);

#ifdef __cplusplus
}
#endif

#endif /* STRING_H */
