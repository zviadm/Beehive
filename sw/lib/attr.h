#ifndef _ATTR_H_
#define _ATTR_H_

#define MCPAD 32

/* Function attributes */
#define __noret__ __attribute__((__noreturn__))

/* Variable attributes */
#define __mcalign__ __attribute__((__aligned__((MCPAD))))

#endif
