/* Implementation of Objective-C Time object
   Copyright (C) 1993,1994, 1995, 1996 Free Software Foundation, Inc.

   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: May 1993

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
*/ 

#include <config.h>
#include <gnustep/base/Time.h>
#include <gnustep/base/Array.h>
#include <unistd.h>    /* _SC_CLK_TCK on SunOS 4 */

#if HAVE_SYS_RUSAGE_H
#include <sys/rusage.h>
#elif HAVE_UCBINCLUDE_SYS_RESOURCE_H
#include <ucbinclude/sys/resource.h>
#endif

#if HAVE_TIMES
#include <sys/times.h> 
#endif /* HAVE_TIMES */

/* There are several places where I need to deal with tz more intelligently */
/* I should allow customization of a strftime() format string for printing. */

#ifdef _SEQUENT_
/* Sequent does not provide us with gettimeofday(). */
int gettimeofday(tvp, tzp)
  struct timeval *tvp;
  struct timezone *tzp;
{
  /* struct timespec is struct timeval with nanosecond resolution */
  /* requires <sys/timers.h> */
  static struct timespec tsp;

  getclock(TIMEOFDAY, &tsp);
  tvp->tv_sec = tsp.tv_sec;
  tvp->tv_usec = (time_t)(tsp.tv_nsec/1000);

  if (tzp) {
    /* set external variables timezone (seconds between timezone */
    /* and UTC), altzone (seconds between alternate timezone and */
    /* UTC), and daylight (non-zero if alternate timezone) based */
    /* on TZ environment variable */
    /* requires <time.h> */
    tzset();
    tzp->tz_minuteswest = (int)(timezone/60);
    tzp->tz_dsttime = daylight;
  }
}
#endif /* _SEQUENT_ */

#ifdef __WIN32__
#include <time.h>
/* Win32 does not provide gettimeofday() */
int gettimeofday(tvp, tzp)
  struct timeval *tvp;
  struct timezone *tzp;
{
  TIME_ZONE_INFORMATION sys_time_zone;
  SYSTEMTIME sys_time;
  struct tm timem;

  // Get the time zone information
  GetTimeZoneInformation(&sys_time_zone);

  // Get the local time
  GetLocalTime(&sys_time);

  timem.tm_sec = sys_time.wSecond;
  timem.tm_min = sys_time.wMinute;
  timem.tm_hour = sys_time.wHour;
  timem.tm_yday = 0;
  timem.tm_mday = sys_time.wDay;
  timem.tm_year = sys_time.wYear - 1900;
  timem.tm_wday = sys_time.wDayOfWeek;
  timem.tm_mon = sys_time.wMonth - 1;

  if (tvp)
    {
      tvp->tv_usec = sys_time.wMilliseconds;
      tvp->tv_sec = mktime(&timem);
    }

  if (tzp)
    {
      tzp->tz_minuteswest = sys_time_zone.Bias;
      tzp->tz_dsttime = sys_time_zone.StandardBias != sys_time_zone.Bias;
    }

  return 0;
}

/* Win32 does not provide times() */
int times(struct tms *atms)
{
  return 0;
}

#endif /* __WIN32__ */

/* tmp for passing to gettimeofday() */
static struct timeval _Time_tv;
static struct timezone _Time_tz;

id dayNames;
id monthNames;

@implementation Time

+ (void) initialize
{
  if (self == [Time class])
    {
#if 0
      /* We should substitute this with a way to make internationalization
	 more easy. */
      /* Should these indeces start at 1?  I think that would be ugly. */
      /* We could switch these to Dictionary's if we want */
      dayNames = [[Array alloc] initWithType:@encode(char*) capacity:7];
      [dayNames putElement:"Monday" atKey:0];
      [dayNames putElement:"Tuesday" atKey:1];
      [dayNames putElement:"Wednesday" atKey:2];
      [dayNames putElement:"Thursday" atKey:3];
      [dayNames putElement:"Friday" atKey:4];
      [dayNames putElement:"Saturday" atKey:5];
      [dayNames putElement:"Sunday" atKey:6];
      monthNames = [[Array alloc] initWithType:@encode(char*) capacity:12];
      [monthNames putElement:"January" atKey:0];
      [monthNames putElement:"February" atKey:1];
      [monthNames putElement:"March" atKey:2];
      [monthNames putElement:"April" atKey:3];
      [monthNames putElement:"May" atKey:4];
      [monthNames putElement:"June" atKey:5];
      [monthNames putElement:"July" atKey:6];
      [monthNames putElement:"August" atKey:7];
      [monthNames putElement:"September" atKey:8];
      [monthNames putElement:"October" atKey:9];
      [monthNames putElement:"November" atKey:10];
      [monthNames putElement:"December" atKey:11];
#endif
    }
}

+ (long) secondClockValue
{
  gettimeofday(&_Time_tv, &_Time_tz);
  return _Time_tv.tv_sec;
}

+ getClockValueSeconds: (long *)sec microseconds: (long *)usec
{
  gettimeofday(&_Time_tv, &_Time_tz);
  *sec = _Time_tv.tv_sec;
  *usec = _Time_tv.tv_usec;
  return self;
}
  
+ (long) millisecondsToRun: (void(*)())aFunc
{
#if HAVE_TIMES
  /* As of Solaris 2.4, getrusage is not supported with the system libraries 
     or with multi-threaded applications.  Thus, we use the times() call  
     instead. */ 
  struct tms start_tms, end_tms; 

  times(&start_tms); 
  (*aFunc)(); 
  times(&end_tms);   
 
  /* CLK_TCK is the number of clock ticks each second */ 
#ifndef CLK_TCK
#define CLK_TCK sysconf(_SC_CLK_TCK) /* sysconf(3) */
#endif
  return ((long)((end_tms.tms_utime - start_tms.tms_utime + 
                end_tms.tms_stime - start_tms.tms_stime) * 1000) / CLK_TCK); 
#elif defined(__WIN32__) || defined(_WIN32)
  DWORD start_tick, end_tick;

  start_tick = GetTickCount();
  (*aFunc)(); 
  end_tick = GetTickCount();
  return ((long)(end_tick - start_tick));
#else 
  struct rusage start_ru, end_ru;
  
  getrusage(RUSAGE_SELF, &start_ru);
  (*aFunc)();
  getrusage(RUSAGE_SELF, &end_ru);
  return ((end_ru.ru_utime.tv_sec - start_ru.ru_utime.tv_sec +
	   end_ru.ru_stime.tv_sec - start_ru.ru_stime.tv_sec) * 1000 + 
	  (end_ru.ru_utime.tv_usec - start_ru.ru_utime.tv_usec +
	   end_ru.ru_stime.tv_usec - start_ru.ru_stime.tv_usec) / 1000);
#endif /* solaris */
  /* should add a warning on overflow. */
}

+ getSeconds: (long *)sec microseconds: (long *)usec toRun: (void(*)())aFunc
{
#if HAVE_TIMES
  struct tms start_tms, end_tms; 
#elif defined(__WIN32__) || defined(_WIN32)
  DWORD start_tick, end_tick;
#else 
  struct rusage start_ru, end_ru;
#endif /* solaris */ 

  [self notImplemented:_cmd];
#if HAVE_TIMES
  times(&start_tms); 
  (*aFunc)(); 
  times(&end_tms); 
#elif defined(__WIN32__) || defined(_WIN32)
#else 
  getrusage(RUSAGE_SELF, &start_ru);
  (*aFunc)();
  getrusage(RUSAGE_SELF, &end_ru);
#endif /* solaris */ 
  return self;
}

+ (unsigned) indexOfDayName: (const char *)dayName
{
  [self notImplemented: _cmd];
  return 0;
}

+ (const char *) nameOfDayIndex: (unsigned)dayIndex
{
  [self notImplemented: _cmd];
  return "";
}

+ (unsigned) indexOfMonthName: (const char *)monthName
{
  [self notImplemented: _cmd];
  return 0;
}

+ (const char *) nameOfMonthIndex: (unsigned)monthIndex
{
  [self notImplemented: _cmd];
  return "";
}

+ (unsigned) daysInMonthIndex: (unsigned)monthIndex forYear: (unsigned)year
{
  [self notImplemented:_cmd];
  return 0;
}

+ (unsigned) daysInYear: (unsigned)year
{
  [self notImplemented:_cmd];
  return 0;
}

+ (BOOL) leapYear: (unsigned)year
{
  [self notImplemented:_cmd];
  return NO;
}


- initNow
{
  [super init];
  gettimeofday(&tv, &tz);
  return self;
}

- initDayIndex: (unsigned)dayIndex 
    monthIndex: (unsigned)monthIndex 
    year: (unsigned)year
{
  [self notImplemented:_cmd];
  [super init];
  return self;
}

- initSeconds: (long)numSeconds microseconds: (long)numMicroseconds
{
  [super init];
  gettimeofday(&tv, &tz);	/* to fill tz */
  tv.tv_sec = numSeconds;
  tv.tv_usec = numMicroseconds;
  return self;
}

- initSeconds: (long)numSeconds
{
  [super init];
  gettimeofday(&tv, &tz);	/* to fill tz */
  tv.tv_sec = numSeconds;
  tv.tv_usec = 0;
  return self;
}

- setSeconds: (long)numSeconds microseconds: (long)numMicroseconds
{
  tv.tv_sec = numSeconds;
  tv.tv_usec = numMicroseconds;
  return self;
}

- setSeconds: (long)numSeconds
{
  tv.tv_sec = numSeconds;
  return self;
}

- (long) days
{
  return tv.tv_sec / (60 * 60 * 24);
}

- (long) hours
{
  return tv.tv_sec / (60 * 60);
}

- (long) minutes
{
  return tv.tv_sec / 60;
}

- (long) seconds
{
  return tv.tv_sec;
}

- (long) microseconds;
{
  return tv.tv_usec;
}


/* I should do something smart with tz */
  
- addTime: (Time *)aTimeObj
{
  tv.tv_sec += [aTimeObj seconds];
  tv.tv_usec += [aTimeObj microseconds];
  return self;
}

- addDays: (unsigned)num
{
  tv.tv_sec += num * 60 * 60 * 24;
  return self;
}

- addHours: (unsigned)num
{
  tv.tv_sec += num * 60 * 60;
  return self;
}

- addMinutes: (unsigned)num
{
  tv.tv_sec += num * 60;
  return self;
}

- addSeconds: (unsigned)num
{
  tv.tv_sec += num;
  return self;
}


- subtractTime: (Time *)aTimeObj
{
  tv.tv_sec -= [aTimeObj seconds];
  tv.tv_usec -= [aTimeObj microseconds];
  return self;
}

- subtractDays: (unsigned)num
{
  tv.tv_sec -= num * 60 * 60 * 24;
  return self;
}

- subtractHours: (unsigned)num
{
  tv.tv_sec -= num * 60 * 60;
  return self;
}

- subtractMinutes: (unsigned)num
{
  tv.tv_sec -= num * 60;
  return self;
}

- subtractSeconds: (unsigned)num
{
  tv.tv_sec -= num;
  return self;
}


- printForDebugger
{
  if ([self days])
    printf("%ld days, %ld:%ld:%ld.%3ld\n", 
	   [self days], [self hours], [self minutes], 
	   [self seconds], [self microseconds]);
  else
    printf("%ld:%ld:%ld.%3ld\n", [self hours], [self minutes], 
	   [self seconds], [self microseconds]);
  return self;
}

- (BOOL) isEqual: anObject
{
  if ([anObject isKindOf:[Time class]]
      && [anObject seconds] == tv.tv_sec
      && [anObject microseconds] == tv.tv_usec)
    return YES;
  else
    return NO;
}

- (int) compare: anObject
{
  int diff;
  
  if (![anObject isKindOf:[Time class]])
    return 17;	/* what non-zero should be returned in cases like this? */
  diff = tv.tv_sec - [anObject seconds];
  if (diff)
    return diff;
  diff = tv.tv_usec - [anObject microseconds];
  return diff;
}

- (void) encodeWithCoder: anEncoder
{
  [self notImplemented:_cmd];
}

+ newWithCoder: aDecoder
{
  [self notImplemented:_cmd];
  return self;
}

- write: (TypedStream*)aStream
{
  // archive inst vars;
  [self notImplemented:_cmd];
  [super write:aStream];
  return self;
}

- read: (TypedStream*)aStream
{
  // archive inst vars;
  [self notImplemented:_cmd];
  [super read:aStream];
  return self;
}

@end

