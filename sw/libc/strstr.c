#include <string.h>

/*
 * Return pointer to first occurrence of str2 in str1, or NULL.
 * Both are assumed to be non-null and correctly null-terminated.
 *
 * For now, we don't care about performance.
 */

char *strstr(const char *str1,const char *str2) {
  for (;;) {
    const char *x1 = str1;
    const char *x2 = str2;
    for (;;) {
      if (*x1 != *x2) break;
      if (*x2 == 0) return (char *)str1;
      if (*x1 == 0) break;
      x1++;
      x2++;
    }
    if (*str1 == 0) return NULL;
    str1++;
  }
}
