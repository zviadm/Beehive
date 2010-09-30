#ifndef STDIO_H
#define STDIO_H

#include <stddef.h>
#include <stdarg.h>



extern int availc();




/* ------------------------------------------------------------
   STDIO
   ------------------------------------------------------------ */






typedef struct _iobuf
{
	char*	_ptr;
	int	_cnt;
	char*	_base;
	int	_flag;
	int	_file;
	int	_charbuf;
	int	_bufsiz;
	char*	_tmpfname;
} FILE;


#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

#define _iob	(*_imp___iob)	/* An array of FILE */

#define stdin	(&_iob[STDIN_FILENO])
#define stdout	(&_iob[STDOUT_FILENO])
#define stderr	(&_iob[STDERR_FILENO])



#ifdef __cplusplus
extern "C" {
#endif

/*
 * File Operations
 */
extern FILE* fopen (const char*, const char*);
extern FILE* freopen (const char*, const char*, FILE*);
extern int fflush (FILE*);
extern int fclose (FILE*);
extern int remove (const char*);
extern int rename (const char*, const char*);

/*
 * Formatted Output
 */
extern int fprintf (FILE*, const char*, ...);
extern int printf (const char*, ...);
extern int sprintf (char*, const char*, ...);
extern int snprintf (char*, size_t, const char*, ...);
extern int vfprintf (FILE*, const char*, va_list);
extern int vprintf (const char*, va_list);
extern int vsprintf (char*, const char*, va_list);
extern int vsnprintf (char*, size_t, const char*, va_list);

/*
 * Formatted Input
 */
extern int fscanf (FILE*, const char*, ...);
extern int scanf (const char*, ...);
extern int sscanf (const char*, const char*, ...);

/*
 * Character Input and Output Functions
 */
extern int fgetc (FILE*);
extern char* fgets (char*, int, FILE*);
extern int fputc (int, FILE*);
extern int fputs (const char*, FILE*);
extern char* gets (char*);
extern int puts (const char*);
extern int ungetc (int, FILE*);

extern int getc (FILE*);
extern int putc (int, FILE*);
extern int getchar (void);
extern int putchar (int);

/*
 * Direct Input and Output Functions
 */
extern size_t fread (void*, size_t, size_t, FILE*);
extern size_t fwrite (const void*, size_t, size_t, FILE*);

/*
 * File Positioning Functions
 */
extern int fseek (FILE*, long, int);
extern long ftell (FILE*);
extern void rewind (FILE*);

typedef long long fpos_t;

extern int fgetpos (FILE*, fpos_t*);
extern int fsetpos (FILE*, const fpos_t*);

/*
 * Error Functions
 */
extern int feof (FILE*);
extern int ferror (FILE*);

extern void clearerr (FILE*);
extern void perror (const char*);







#endif /* STDIO_H */
