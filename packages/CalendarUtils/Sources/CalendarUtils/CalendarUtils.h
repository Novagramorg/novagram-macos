

#import <Foundation/Foundation.h>

@interface CalendarUtils : NSObject

@property (class, nonatomic, readonly) NSInteger yearForNoYear;
+ (BOOL) isYearHidden:(NSInteger)year;

+ (BOOL) isSameDate:(NSDate*)d1 date:(NSDate*)d2 checkDay:(BOOL)checkDay;
+ (NSString*) dd:(NSDate*)d;
+ (NSInteger) colForDay:(NSInteger)day;
+ (NSInteger) lastDayOfTheMonth:(NSDate *)date;
+ (NSDate*) toUTC:(NSDate*)d;
+ (NSDate*) monthDay:(NSInteger)day date:(NSDate *)date;
+ (NSInteger)weekDay:(NSDate *)date;
+ (NSDate *) stepMonth:(NSInteger)dm date:(NSDate *)date;
+ (NSDate *) year:(NSInteger)dm date:(NSDate *)date;
+ (NSDate *) year:(NSInteger)dm date:(NSDate *)date day:(NSInteger)day;
@end
