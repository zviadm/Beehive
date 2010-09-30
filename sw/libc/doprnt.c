#include <stdio.h>
#include <stdarg.h>
#include <doprnt.h>



/* ------------------------------------------------------------
   Process a format string, taking arguments from a varargs list.
   Each character c generated is passed to put(c,env).  Returns the
   number of characters output.
   ------------------------------------------------------------ */

int
_doprnt (const char * format,
         va_list ap,
         void (*put)(char,void*),
         void * env)
{
  int n = 0;

  for (;;) {
    int c = *format++;
    if (c == 0) return n;
    
    if (c != '%') {
      put(c,env);
      n++;
      continue;
    }
    

    /* Start processing a format specifier.  The first characters
       after the % give some flags.  */

    int leftj = 0;     /* left justification */
    int lfill = ' ';   /* left fill character */
    int width = 0;     /* width specification */
    int prec = 0;      /* precision specification */
    int longc = 0;     /* how many longs in argument */

    int sign = 0;
    unsigned long long radix;
    unsigned long long value;
    const char * digit;


    
    c = *format++;

    if (c == '-') { leftj = 1; c = *format++; }
    if (c == '0') { lfill = c; c = *format++; }
    

    /* Get the width specification. */

    if (c == '*') {
      width = va_arg(ap,int);
      if (width < 0) width = -width;
      c = *format++;
    }
    else while ('0' <= c && c <= '9') {
      width = width*10 + c - '0';
      c = *format++;
    }
      

    /* Get the precision specification, if there is one. */

    if (c == '.') {
      c = *format++;

      if (c == '*') {
	prec = va_arg(ap,int);
	if (prec < 0) prec = -prec;
	c = *format++;
      }
      else while ('0' <= c && c <= '9') {
	prec = prec*10 + c - '0';
	c = *format++;
      }
    }


    /* Count how long is argument. */

    while (c == 'l') {
      longc++;
      c = *format++;
    }




    /* Initialize the buffer in which to generate formatted
       characters.  Formatted characters are composed backwards (right
       to left) using pointer pbuf.  Start out with the terminating
       null character.  Strings do not use the buffer but instead
       aim pbuf directly at the string.  */

    char buf [40];
    char * pbuf = buf + sizeof(buf);
    *--pbuf = 0;


    /* Process the specifier and generate formatted characters. */

    switch (c) {
    case 0:
      return n;


    case '%':
      *--pbuf = '%';
      break;


    case 'c':  /* Character. */
      *--pbuf = va_arg(ap,int);
      break;


    case 's':  /* String. */
      pbuf = va_arg(ap,char*);
      break;


    case 'd':  /* Signed decimal integer. */
      sign = 1;
      radix = 10;
      digit = "0123456789";
      goto intvalue;


    case 'u':  /* Unsigned decimal integer. */
      sign = 0;
      radix = 10;
      digit = "0123456789";
      goto intvalue;


    case 'o':  /* Unsigned octal integer. */
      sign = 0;
      radix = 8;
      digit = "0123456789";
      goto intvalue;
      

    case 'x':  /* Unsigned hexadecimal integer (lower case). */
      sign = 0;
      radix = 16;
      digit = "0123456789abcdef";
      goto intvalue;


    case 'X':  /* Unsigned hexadecimal integer (upper case). */
      sign = 0;
      radix = 16;
      digit = "0123456789ABCDEF";
      goto intvalue;


    intvalue:
      if (sign) {
	switch (longc) {
	case 2:  value = (long long int)(va_arg(ap,long long int)); break;
	case 1:  value = (long long int)(va_arg(ap,     long int)); break;
	default: value = (long long int)(va_arg(ap,          int)); break;
	}
	sign = 0;
	if ((long long)value < 0) { value = -value; sign = 1; }
      }
      else {
	switch (longc) {
	case 2:  value = va_arg(ap,unsigned long long int); break;
	case 1:  value = va_arg(ap,unsigned      long int); break;
	default: value = va_arg(ap,unsigned           int); break;
	}
      }
      do {
	*--pbuf = digit[value % radix];
	value /= radix;
      } while (value != 0);
      if (sign) *--pbuf = '-';
      break;


    default:
      break;
    }


    /* Count formatted characters and compute padding. */

    int lpadn = width;
    char * p = pbuf;
    while (*p != 0) { p++; lpadn--; }

    if (lpadn < 0) lpadn = 0;
    int rpadn = 0;
    

    /* For left justification, place padding on the right. */

    if (leftj) {
      rpadn = lpadn;
      lpadn = 0;
    }

    
    /* Output padding and formatted characters. */

    while (lpadn != 0) { put(lfill,env); n++; lpadn--; }
    while (*pbuf != 0) { put(*pbuf++,env); n++; }
    while (rpadn != 0) { put(' ',env); n++; rpadn--; }
  }
}
