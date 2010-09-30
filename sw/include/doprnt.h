#ifndef DOPRNT_H
#define DOPRNT_H

#include <stdarg.h>



/* ------------------------------------------------------------
   DOPRNT
   ------------------------------------------------------------ */


extern int _doprnt (const char * format,va_list ap,
		    void (*put)(char,void*),void * env);



#endif /* DOPRNT_H */
