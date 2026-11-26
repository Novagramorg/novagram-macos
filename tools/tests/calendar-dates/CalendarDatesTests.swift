import AppKit
import CalendarUtils
import XCTest

var systemCalendar=Calendar(identifier:.gregorian)
var testNow=Date(timeIntervalSince1970:0)
var testLocale=Locale(identifier:"en_US")
struct Strings {func birthdayYearsOldOther(_ year:Int)->String {"\(year) years"}}
func strings()->Strings {Strings()}
struct TelegramBirthday:Equatable {let day:Int32;let month:Int32;let year:Int32?}
__BIRTHDAY__
__BIRTHDAY_HELPERS__
__FORMAT__
func suggestedDate(_ birthday:TelegramBirthday)->Date? {__SUGGESTED__}
__MONTH__
func enabled(_ day:Int,month:CalendarMonthStruct,now:Date)->Bool {__ENABLED__}
enum ViewControllerStyle {case none}
struct Step {let date:Date;let selected:Bool}
final class Navigation {var steps:[Step]=[];func push(_ step:Step,style:ViewControllerStyle) {steps.append(step)}}
final class CalendarController {
    let navigation=Navigation();let interactions=Interactions();let onlyFuture=false;let lowYear=1900;let limitedBy:Date?=nil;var selectedDate:Date;var isActive=true;var date:Date {selectedDate}
    init(_ date:Date) {self.selectedDate=date}
    func stepMonth(date:Date,selectDayAnyway:Bool=false)->Step {.init(date:date,selected:selectDayAnyway)}
    __HIDE__
    __SELECT_YEAR__
}
struct Appearance {struct Language {var languageCode="en_US"};var language=Language()}
var appAppearance=Appearance()
final class Interactions {let canBeNoYear=true;var years:[Int32]=[];var dates:[Date]=[];func changeYear(_ year:Int32,_ date:Date) {years.append(year);dates.append(CalendarUtils.year(Int(year),date:date))}}
final class MonthController {
    let month:CalendarMonthStruct;let now:Date;let onlyFuture:Bool;let lowYear:Int;let interactions=Interactions()
    init(_ date:Date,now:Date,onlyFuture:Bool=false,lowYear:Int=1900) {month=CalendarMonthStruct(month:date,selectDayAnyway:true,onlyFuture:onlyFuture,limitedBy:nil,dayHandler:{_ in});self.now=now;self.onlyFuture=onlyFuture;self.lowYear=lowYear}
    __NEXT__
    __PREV__
    func label()->(String,String) {__LABEL__}
    func hideYear()->()->Void {__NO_YEAR__}
}
final class CalendarDatesTests:XCTestCase {
    var oldZone:TimeZone!
    override func setUp() {oldZone=NSTimeZone.default;NSTimeZone.default=TimeZone(secondsFromGMT:0)!;systemCalendar=Calendar(identifier:.gregorian);appAppearance=Appearance();testNow=date(2026,10,17);testLocale=Locale(identifier:"en_US")}
    override func tearDown() {NSTimeZone.default=oldZone}
    func date(_ year:Int,_ month:Int,_ day:Int,_ hour:Int=12)->Date {Calendar(identifier:.gregorian).date(from:DateComponents(year:year,month:month,day:day,hour:hour))!}
    func month(_ year:Int,_ month:Int,day:Int=1,future:Bool=false,limit:Date?=nil)->CalendarMonthStruct {CalendarMonthStruct(month:date(year,month,day),selectDayAnyway:true,onlyFuture:future,limitedBy:limit,dayHandler:{_ in})}
    func testHideYearPreservesLeapDay() {let c=CalendarController(date(2000,2,29));c.hideYear();let d=c.navigation.steps[0].date;XCTAssertEqual(d.birthday,.init(day:29,month:2,year:nil));XCTAssertEqual(CalendarUtils.lastDay(ofTheMonth:d),29);XCTAssertTrue(c.navigation.steps[0].selected)}
    func testNoYearMenuAllowsLeapDay() {let c=MonthController(date(2000,2,29),now:date(2026,10,17));c.hideYear()();let d=c.interactions.dates[0];XCTAssertEqual(CalendarUtils.lastDay(ofTheMonth:d),29);XCTAssertEqual(CalendarUtils.monthDay(29,date:d).birthday,.init(day:29,month:2,year:nil))}
    func testHideYearPreservesAllMonthDays() {for (m,d) in [(1,31),(2,29),(3,31),(4,30),(5,31),(6,30),(7,31),(8,31),(9,30),(10,31),(11,30),(12,31)] {let c=CalendarController(date(2000,m,d));c.hideYear();XCTAssertEqual(c.navigation.steps[0].date.birthday,.init(day:Int32(d),month:Int32(m),year:nil))}}
    func testLegacyNoYearStillDecodes() {XCTAssertEqual(date(1,8,9).birthday,.init(day:9,month:8,year:nil))}
    func testNormalBirthdayKeepsYear() {XCTAssertEqual(date(2000,2,29).birthday,.init(day:29,month:2,year:2000))}
    func testBuddhistSystemCalendarCannotChangeBirthday() {systemCalendar=Calendar(identifier:.buddhist);XCTAssertEqual(date(1990,7,15).birthday,.init(day:15,month:7,year:1990))}
    func testIslamicSystemCalendarCannotChangeBirthday() {systemCalendar=Calendar(identifier:.islamicCivil);XCTAssertEqual(date(1990,7,15).birthday,.init(day:15,month:7,year:1990))}
    func testJapaneseSystemCalendarCannotChangeBirthday() {systemCalendar=Calendar(identifier:.japanese);XCTAssertEqual(date(1990,7,15).birthday,.init(day:15,month:7,year:1990))}
    func testHiddenYearSurvivesBuddhistCalendar() {systemCalendar=Calendar(identifier:.buddhist);let c=CalendarController(date(2000,2,29));c.hideYear();XCTAssertEqual(c.navigation.steps[0].date.birthday,.init(day:29,month:2,year:nil))}
    func testHideYearUsesGregorianDayWithIslamicCalendar() {systemCalendar=Calendar(identifier:.islamicCivil);let c=CalendarController(date(2000,6,15));c.hideYear();XCTAssertEqual(c.navigation.steps[0].date.birthday,.init(day:15,month:6,year:nil))}
    func testHiddenYearLabelAndNavigationBoundaries() {let c=CalendarController(date(2000,1,15));c.hideYear();let jan=MonthController(c.navigation.steps[0].date,now:date(2026,10,17));XCTAssertEqual(jan.label().1,"—");XCTAssertFalse(jan.isPrevEnabled);XCTAssertTrue(jan.isNextEnabled);let december:Date=CalendarUtils.monthDay(15,date:CalendarUtils.stepMonth(11,date:jan.month.month));let dec=MonthController(december,now:date(2026,10,17));XCTAssertFalse(dec.isNextEnabled);XCTAssertTrue(dec.isPrevEnabled)}
    func testCalendarLabelUsesGregorianYearWithBuddhistLocale() {appAppearance.language.languageCode="th_TH@calendar=buddhist";let c=MonthController(date(2000,7,1),now:date(2026,10,17));let f=DateFormatter();f.locale=Locale(identifier:appAppearance.language.languageCode);f.calendar=Calendar(identifier:.gregorian);f.dateFormat="yyyy";XCTAssertEqual(c.label().1,f.string(from:c.month.month))}
    func testGridStartsOnCorrectWeekdayAcrossSpringDST() {NSTimeZone.default=TimeZone(identifier:"Europe/Berlin")!;let d=date(2024,4,15,0);let m=CalendarMonthStruct(month:d,selectDayAnyway:true,onlyFuture:false,limitedBy:nil,dayHandler:{_ in});XCTAssertEqual(m.currentStartDay,1)}
    func testGridStartsOnCorrectWeekdayAcrossFallDST() {NSTimeZone.default=TimeZone(identifier:"America/New_York")!;let d=date(2024,11,20,0);let m=CalendarMonthStruct(month:d,selectDayAnyway:true,onlyFuture:false,limitedBy:nil,dayHandler:{_ in});XCTAssertEqual(m.currentStartDay,5)}
    func testGridIndependentOfSelectedDayAndTimeAcrossZones() {for zone in ["UTC","Europe/Berlin","America/New_York","Australia/Sydney"] {NSTimeZone.default=TimeZone(identifier:zone)!;let calendar=Calendar(identifier:.gregorian);for mon in 1...12 {let start=date(2024,mon,1);let expected=(calendar.component(.weekday,from:start)+5)%7+1;for day in [1,15,28] {for hour in [0,12,23] {let m=CalendarMonthStruct(month:date(2024,mon,day,hour),selectDayAnyway:true,onlyFuture:false,limitedBy:nil,dayHandler:{_ in});XCTAssertEqual(m.currentStartDay,expected,"\(zone) \(mon)/\(day) \(hour)")}}}}}
    func testUpperLimitAcrossMonthKeepsEarlierValidDays() {let m=month(2026,10,future:true,limit:date(2026,11,3));XCTAssertTrue(enabled(29,month:m,now:date(2026,10,28)));XCTAssertTrue(enabled(31,month:m,now:date(2026,10,28)))}
    func testUpperLimitAcrossYearKeepsDecemberDays() {let m=month(2026,12,future:true,limit:date(2027,1,3));XCTAssertTrue(enabled(29,month:m,now:date(2026,12,28)));XCTAssertTrue(enabled(31,month:m,now:date(2026,12,28)))}
    func testUpperLimitInsideMonthIsInclusive() {let m=month(2026,10,future:true,limit:date(2026,10,20,0));XCTAssertTrue(enabled(20,month:m,now:date(2026,10,17)));XCTAssertFalse(enabled(21,month:m,now:date(2026,10,17)))}
    func testUpperLimitPastYearDoesNotRejectEarlierLargerMonth() {let m=month(2024,12,limit:date(2025,1,3));XCTAssertTrue(enabled(31,month:m,now:date(2026,10,17)))}
    func testHistoricalCalendarRejectsLaterMonthsAndYears() {XCTAssertFalse(enabled(1,month:month(2026,11),now:date(2026,10,17)));XCTAssertFalse(enabled(1,month:month(2027,1),now:date(2026,10,17)))}
    func testHistoricalCurrentMonthIncludesTodayOnly() {let m=month(2026,10);XCTAssertTrue(enabled(17,month:m,now:date(2026,10,17)));XCTAssertFalse(enabled(18,month:m,now:date(2026,10,17)))}
    func testFutureCalendarRejectsEarlierMonthsAndYears() {XCTAssertFalse(enabled(30,month:month(2026,9,future:true),now:date(2026,10,17)));XCTAssertFalse(enabled(31,month:month(2025,12,future:true),now:date(2026,10,17)))}
    func testFutureCalendarRejectsBeyondOneYear() {XCTAssertFalse(enabled(1,month:month(2027,11,future:true),now:date(2026,10,17)));XCTAssertFalse(enabled(1,month:month(2028,1,future:true),now:date(2026,10,17)))}
    func testFutureOneYearBoundaryIsInclusive() {let m=month(2027,10,future:true);XCTAssertTrue(enabled(17,month:m,now:date(2026,10,17)));XCTAssertFalse(enabled(18,month:m,now:date(2026,10,17)))}
    func testFutureLeapYearBoundary() {let now=date(2024,2,29);XCTAssertTrue(enabled(28,month:month(2025,2,future:true),now:now));XCTAssertFalse(enabled(1,month:month(2025,3,future:true),now:now))}
    func testFutureTodayUsesCalendarDayNotTimeOfDay() {let m=month(2026,10,future:true);XCTAssertTrue(enabled(17,month:m,now:date(2026,10,17,23)));XCTAssertFalse(enabled(16,month:m,now:date(2026,10,17,0)))}
    func testDayBoundsRejectInvalidIndices() {let m=month(2024,2);XCTAssertFalse(enabled(0,month:m,now:date(2026,10,17)));XCTAssertFalse(enabled(30,month:m,now:date(2026,10,17)));XCTAssertTrue(enabled(29,month:m,now:date(2026,10,17)))}
    func testLimitComparisonAcrossDSTUsesCalendarDay() {NSTimeZone.default=TimeZone(identifier:"America/New_York")!;let m=month(2024,11,future:true,limit:date(2024,11,5));XCTAssertTrue(enabled(5,month:m,now:date(2024,10,30)));XCTAssertFalse(enabled(6,month:m,now:date(2024,10,30)))}
    func testFutureNavigationCannotGoBeforeCurrentMonth() {let c=MonthController(date(2026,9,1),now:date(2026,10,17),onlyFuture:true);XCTAssertFalse(c.isPrevEnabled);XCTAssertTrue(c.isNextEnabled)}
    func testFutureNavigationCannotGoBeyondMaximumMonth() {let c=MonthController(date(2027,11,1),now:date(2026,10,17),onlyFuture:true);XCTAssertFalse(c.isNextEnabled);XCTAssertTrue(c.isPrevEnabled)}
    func testHistoricalNavigationCannotGoFurtherIntoFuture() {let c=MonthController(date(2026,11,1),now:date(2026,10,17));XCTAssertFalse(c.isNextEnabled);XCTAssertTrue(c.isPrevEnabled)}
    func testNavigationAtValidBounds() {let now=date(2026,10,17);let current=MonthController(now,now:now,onlyFuture:true);XCTAssertFalse(current.isPrevEnabled);XCTAssertTrue(current.isNextEnabled);let last=MonthController(date(2027,10,1),now:now,onlyFuture:true);XCTAssertFalse(last.isNextEnabled);XCTAssertTrue(last.isPrevEnabled);let historical=MonthController(now,now:now);XCTAssertFalse(historical.isNextEnabled);let first=MonthController(date(1900,1,1),now:now);XCTAssertFalse(first.isPrevEnabled)}

    func testSuggestedNoYearLeapBirthdayRoundTrips() {let birthday=TelegramBirthday(day:29,month:2,year:nil);let d=suggestedDate(birthday);XCTAssertNotNil(d);XCTAssertEqual(d?.birthday,birthday)}
    func testSuggestedKnownBirthdayRoundTripsUnderBuddhistCalendar() {systemCalendar=Calendar(identifier:.buddhist);let birthday=TelegramBirthday(day:29,month:2,year:2000);XCTAssertEqual(suggestedDate(birthday)?.birthday,birthday);if let d=suggestedDate(birthday) {XCTAssertEqual(Calendar(identifier:.gregorian).component(.year,from:d),2000)}}
    func testSuggestedBirthdayRejectsInvalidDates() {for birthday in [TelegramBirthday(day:30,month:2,year:nil),.init(day:29,month:2,year:2001),.init(day:1,month:13,year:2000),.init(day:0,month:1,year:2000)] {XCTAssertNil(suggestedDate(birthday))}}
    func testBirthdayTodayUnderBuddhistCalendar() {systemCalendar=Calendar(identifier:.buddhist);let b=TelegramBirthday(day:17,month:10,year:1990);XCTAssertTrue(b.isToday);XCTAssertTrue(b.isEligble)}
    func testBirthdayTodayUnderIslamicCalendar() {systemCalendar=Calendar(identifier:.islamicCivil);let b=TelegramBirthday(day:17,month:10,year:nil);XCTAssertTrue(b.isToday);XCTAssertFalse(b.isTomorrow());XCTAssertFalse(b.isYesterday())}
    func testBirthdayTomorrowAcrossYearBoundaryWithIslamicCalendar() {systemCalendar=Calendar(identifier:.islamicCivil);testNow=date(2026,12,31);let b=TelegramBirthday(day:1,month:1,year:nil);XCTAssertTrue(b.isTomorrow());XCTAssertTrue(b.isEligble)}
    func testBirthdayYesterdayAcrossYearBoundaryWithIslamicCalendar() {systemCalendar=Calendar(identifier:.islamicCivil);testNow=date(2027,1,1);let b=TelegramBirthday(day:31,month:12,year:nil);XCTAssertTrue(b.isYesterday());XCTAssertTrue(b.isEligble)}
    func testBirthdayRelativeDaysAcrossDST() {NSTimeZone.default=TimeZone(identifier:"America/New_York")!;testNow=date(2024,3,10,23);XCTAssertTrue(TelegramBirthday(day:11,month:3,year:nil).isTomorrow());XCTAssertTrue(TelegramBirthday(day:9,month:3,year:nil).isYesterday())}
    func testBirthdayTomorrowOnLeapDay() {testNow=date(2024,2,28);XCTAssertTrue(TelegramBirthday(day:29,month:2,year:nil).isTomorrow());testNow=date(2025,2,28);XCTAssertFalse(TelegramBirthday(day:29,month:2,year:nil).isTomorrow())}
    func testBirthdayAgeUsesGregorianYearWithBuddhistCalendar() {systemCalendar=Calendar(identifier:.buddhist);XCTAssertEqual(TelegramBirthday(day:17,month:10,year:1990).yearsSince(),36)}
    func testBirthdayAgeUsesGregorianYearWithJapaneseCalendar() {systemCalendar=Calendar(identifier:.japanese);XCTAssertEqual(TelegramBirthday(day:17,month:10,year:1990).yearsSince(),36)}
    func testBirthdayAgeBeforeAndAfterBirthday() {XCTAssertEqual(TelegramBirthday(day:18,month:10,year:1990).yearsSince(),35);XCTAssertEqual(TelegramBirthday(day:16,month:10,year:1990).yearsSince(),36);XCTAssertNil(TelegramBirthday(day:17,month:10,year:nil).yearsSince())}
    func testInvalidBirthdayHasNoAge() {XCTAssertNil(TelegramBirthday(day:30,month:2,year:2000).yearsSince());XCTAssertNil(TelegramBirthday(day:1,month:13,year:2000).yearsSince())}
    func testNoYearLeapBirthdayFormatting() {XCTAssertEqual(formatBirthdayToString(day:29,month:2,year:nil),"Feb 29")}
    func testBirthdayFormattingRejectsInvalidDate() {XCTAssertNil(formatBirthdayToString(day:30,month:2,year:nil));XCTAssertNil(formatBirthdayToString(day:29,month:2,year:2001));XCTAssertNil(formatBirthdayToString(day:1,month:13,year:2000))}
    func testBirthdayFormattingUsesGregorianDateWithIslamicSystemCalendar() {systemCalendar=Calendar(identifier:.islamicCivil);XCTAssertEqual(formatBirthdayToString(day:17,month:10,year:nil),"Oct 17")}
    func testBirthdayFormattingUsesGregorianYearWithBuddhistLocale() {systemCalendar=Calendar(identifier:.buddhist);testLocale=Locale(identifier:"th_TH@calendar=buddhist");let f=DateFormatter();f.locale=testLocale;f.calendar=Calendar(identifier:.gregorian);f.dateStyle = .medium;f.timeStyle = .none;XCTAssertEqual(formatBirthdayToString(day:17,month:10,year:1990),f.string(from:date(1990,10,17)))}
    func testBirthdayFormattedAgeUsesCorrectGregorianAge() {systemCalendar=Calendar(identifier:.buddhist);testLocale=Locale(identifier:"en_US");let b=TelegramBirthday(day:17,month:10,year:1990);XCTAssertTrue(b.formattedYears.hasPrefix("🎂 "));XCTAssertTrue(b.formattedYears.hasSuffix("(36 years)"))}

}
