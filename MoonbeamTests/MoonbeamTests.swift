//
//  MoonbeamTests.swift
//  MoonbeamTests
//
//  Created by jack on 6/4/25.
//

import Foundation
import Testing
@testable import Moonbeam

struct MoonbeamTests {

    @Test func sunEventsDecodeAllTwilightsAndISOTimeFormats() throws {
        let data = Data(#"""
        {
          "sunrise": "2026-10-22T07:30:00+02:00",
          "sunset": "2026-10-22T18:18:00.000+02:00",
          "civil_twilight_begin": "2026-10-22T07:02:00+02:00",
          "civil_twilight_end": "2026-10-22T18:46:00+02:00",
          "nautical_twilight_begin": "2026-10-22T06:30:00+02:00",
          "nautical_twilight_end": "2026-10-22T19:18:00+02:00",
          "astronomical_twilight_begin": "2026-10-22T05:58:00+02:00",
          "astronomical_twilight_end": "2026-10-22T19:50:00+02:00"
        }
        """#.utf8)
        let events = try JSONDecoder().decode(SunEventTimes.self, from: data)
        let ordered = [events.astronomicalDawn, events.nauticalDawn, events.civilDawn,
                       events.sunrise, events.sunset, events.civilDusk,
                       events.nauticalDusk, events.astronomicalDusk]
        #expect(ordered.allSatisfy { $0 != nil })
        let dates = ordered.compactMap { $0 }
        #expect(dates == dates.sorted())
        let sunrise = try #require(events.sunrise)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(utc.component(.hour, from: sunrise) == 5)
        #expect(utc.component(.minute, from: sunrise) == 30)
    }

    @Test func missingSunEventsStayUnavailable() throws {
        let events = try JSONDecoder().decode(SunEventTimes.self,
            from: Data(#"{"sunrise":null,"civil_twilight_begin":"not-a-date"}"#.utf8))
        #expect(events.sunrise == nil)
        #expect(events.sunset == nil)
        #expect(events.civilDawn == nil)
        #expect(events.astronomicalDusk == nil)
    }

    private func makePlan(localOffset: Int, destOffset: Int, nights: Int = 3) -> JetLagPlan {
        JetLagPlanCalculator.generatePlan(
            originName: "Origin",
            destinationCity: "Destination",
            nightCount: nights,
            originSunrise: 390,
            originSunset: 1200,
            destSunrise: 390,
            destSunset: 1200,
            localOffsetHours: localOffset,
            destOffsetHours: destOffset
        )
    }

    @Test func shiftNormalizesToShortestDirection() {
        // SF (−7) → Sumatra/WIB (+7): raw +14 h should become a −10 h delay.
        #expect(JetLagPlan.normalizedShiftMinutes(localOffsetHours: -7, destOffsetHours: 7) == -600)
        // SF (−7) → London (+1): +8 h advance stays +8 h.
        #expect(JetLagPlan.normalizedShiftMinutes(localOffsetHours: -7, destOffsetHours: 1) == 480)
        // Same zone: no shift.
        #expect(JetLagPlan.normalizedShiftMinutes(localOffsetHours: 3, destOffsetHours: 3) == 0)
    }

    @Test func finalNightLandsOnDestinationBedtime() {
        // The last night's bedtime, read on the destination clock, must equal
        // the ideal bedtime (22:30).
        for (localOffset, destOffset) in [(-7, 7), (-7, 1), (0, 9), (5, -8), (-8, -8)] {
            let plan = makePlan(localOffset: localOffset, destOffset: destOffset)
            let lastBed = plan.nights.last!.sleepWindow.bedMinutes
            let rawDiffMinutes = (destOffset - localOffset) * 60
            let onDestClock = (((lastBed + rawDiffMinutes) % 1440) + 1440) % 1440
            #expect(onDestClock == 22 * 60 + 30, "offsets \(localOffset)→\(destOffset)")
        }
    }

    @Test func eastwardShiftMovesBedtimeEarlier() {
        // SF → London (+8 h): each night's bedtime should be earlier than the last.
        let plan = makePlan(localOffset: -7, destOffset: 1)
        #expect(plan.nights[0].sleepWindow.bedMinutes == 22 * 60 + 30 - 160)
        #expect(plan.nights[1].sleepWindow.bedMinutes == 22 * 60 + 30 - 320)
        #expect(plan.nights[2].sleepWindow.bedMinutes == 22 * 60 + 30 - 480)
    }

    @Test func sleepDurationIsPreserved() {
        let plan = makePlan(localOffset: -7, destOffset: 7)
        for night in plan.nights {
            #expect(night.sleepWindow.durationMinutes == 8 * 60 + 30)
        }
    }

    @Test func nightsStartTonightAndRunConsecutively() {
        let cal = Calendar.current
        let plan = makePlan(localOffset: -7, destOffset: 1, nights: 3)
        #expect(plan.nights.count == 3)
        #expect(cal.isDateInToday(plan.nights.first!.date))
        for (i, night) in plan.nights.enumerated() {
            let expected = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: Date()))!
            #expect(cal.isDate(night.date, inSameDayAs: expected))
        }
    }

    @Test func destinationSunTimesConvertOntoOriginClock() {
        // Sumatra (+7) seen from SF (−7): a 6:30 AM destination sunrise is
        // 6:30 − (−10 h) = 4:30 PM on the origin clock.
        let plan = makePlan(localOffset: -7, destOffset: 7)
        #expect(plan.tzShiftMinutes == -600)
        #expect(plan.destSunriseLocalMinutes == (390 + 600) % 1440)
    }

    @Test func airportCodeResolvesFromTable() async throws {
        let place = try await JetLagPlanCalculator.resolvePlace("lhr")
        #expect(place.name == "London")
        #expect(place.timeZone.identifier == "Europe/London")
    }
}
