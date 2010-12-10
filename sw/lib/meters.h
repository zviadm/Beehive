#ifndef _METERS_H_
#define _METERS_H_

/*
 * Reset DCache meter counters
 */
void dcache_meters_start( void );

/*
 * Report on changes in meter values since the call to dcache_meters_start()
 */
void dcache_meters_report( void );

#endif
