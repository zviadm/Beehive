#ifndef _METERS_H_
#define _METERS_H_

/*
 * Grab the current values from the meter system
 */
void meters_start( void );

/*
 * report on changes in meter values since the
 * call to meters_start()
 */
void meters_report( void );

#endif
