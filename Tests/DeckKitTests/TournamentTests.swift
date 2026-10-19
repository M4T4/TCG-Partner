import Foundation
import Testing
@testable import DeckKit

@Suite struct AgeDivisionTests {
    let calendar = Calendar(identifier: .gregorian)

    func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func seasonChangesInJuly() {
        #expect(AgeDivision.season(on: date(2026, 6), calendar: calendar) == 2026)
        #expect(AgeDivision.season(on: date(2026, 7), calendar: calendar) == 2027)
        #expect(AgeDivision.season(on: date(2026, 10), calendar: calendar) == 2027)
    }

    /// Temporada 2026: Junior 2014+, Senior 2010–2013, Masters 2009 o antes.
    @Test func season2026() {
        let today = date(2026, 3)
        #expect(AgeDivision.forBirthDate(date(2014, 12), on: today, calendar: calendar) == .junior)
        #expect(AgeDivision.forBirthDate(date(2013, 1), on: today, calendar: calendar) == .senior)
        #expect(AgeDivision.forBirthDate(date(2010, 1), on: today, calendar: calendar) == .senior)
        #expect(AgeDivision.forBirthDate(date(2009, 12), on: today, calendar: calendar) == .masters)
        #expect(AgeDivision.forBirthDate(date(1995, 4), on: today, calendar: calendar) == .masters)
    }

    @Test func boundariesMoveWithSeason() {
        let today = date(2026, 10) // temporada 2027
        #expect(AgeDivision.forBirthDate(date(2014, 6), on: today, calendar: calendar) == .senior)
        #expect(AgeDivision.forBirthDate(date(2010, 6), on: today, calendar: calendar) == .masters)
    }
}
