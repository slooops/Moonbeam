<p align="center">
  <img src="https://developer.apple.com/sf-symbols/" width="0" height="0" />
</p>

<h1 align="center">Moonbeam</h1>

<p align="center">
  <strong>Sleep smarter, not longer.</strong><br/>
  A REM-aware sleep calculator for iOS, built with SwiftUI and liquid glass.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS_26-000000?style=flat&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-007AFF?style=flat&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat" />
</p>

---

## What is this?

Most alarm apps let you set a time. Moonbeam lets you set a *number of complete sleep cycles* -- because waking up mid-cycle is why you feel like garbage even after 9 hours of sleep.

The centerpiece is a circular dial inspired by Apple's Sleep app, but with a twist: instead of continuous time selection, it **snaps to REM cycle boundaries**. Drag either handle freely and the opposite end jumps in 90-minute increments. You always wake at the end of a complete cycle.

The gradient tells a story too -- sunset orange at bedtime fades through deep violet midnight into morning sky blue and sunrise amber at your alarm.

---

## To Do

- [ ] **Alarm integration** -- hook into iOS alarm APIs so Moonbeam can set actual wake alarms with system sounds, not just display times
- [ ] **Alarm sound picker** -- let users choose from system alarm tones or custom sounds
- [ ] **Smart light integration (Apple HomeKit)** -- generate a Home automation to turn on lights at alarm time as a gentle light alarm
- [ ] **Sonos alarm support** -- if Sonos API allows it, set wake alarms on Sonos speakers
- [ ] **Sleep journaling (Tool 1.1)** -- record sleep/wake times without needing a wearable; use data over time to calculate personal sleep cycle length and fall-asleep time automatically
- [ ] **Apple Watch integration (Tool 1.2)** -- pull sleep data from HealthKit/Apple Watch to refine cycle calculations
- [ ] **Onboarding / first-launch** -- explain what REM cycles are and why this app exists
- [ ] **Widget** -- Lock Screen and Home Screen widgets showing next alarm / bedtime

---

## Features

**The Dial**
- 24-hour circular clock face with draggable bedtime and wake-up handles
- Both handles snap to 15-minute increments; the *opposite* handle jumps in whole-cycle chunks
- Drag the arc itself to shift your entire sleep window without changing duration
- Animated REM segment dividers show cycle boundaries within the arc
- Haptic feedback fires on every cycle boundary crossing

**Sleep Profile**
- Customize REM cycle length (75--120 minutes, default 90)
- Customize fall-asleep buffer (0--45 minutes, default 15)
- Settings persist across launches via `@AppStorage`

**Visual Design**
- Liquid glass cards using iOS 26 `.glassEffect()`
- 3D raised dial track with layered shadows and bevel highlights
- Sunset-to-sunrise gradient arc (orange -> rose -> plum -> violet -> midnight blue -> sky -> amber)
- SF Symbols throughout -- zero emoji
- Dark mode only, because you're using this at night

---

## Architecture

```
Moonbeam/
  MoonbeamApp.swift          -- App entry, injects SleepProfile into environment
  ContentView.swift           -- Main screen: dial + Sleep Now button + settings gear
  SleepSliderView.swift       -- The circular dial (the big one -- ~540 lines of custom drawing)
  SleepCalculator.swift       -- Pure math: angle/time conversion, cycle snapping, formatting
  SleepProfile.swift          -- @AppStorage-backed user settings (cycle length, fall-asleep time)
  SleepProfileView.swift      -- Settings sheet with steppers and explanatory text
  View+MoonbeamBackground.swift -- .moonbeamBackground() and .moonbeamCard() modifiers
```

**State flow:** `MoonbeamApp` creates a `SleepProfile` (persisted) and passes it as `@EnvironmentObject`. The dial reads cycle length and fall-asleep time from the profile. All sleep math lives in `SleepCalculator` (a stateless enum with static functions). The dial's internal state (`bedAngle`, `wakeAngle`, `lastDragged`) drives the display angles, which snap the non-active handle to cycle boundaries.

**Coordinate system:** 0 radians = 12:00 AM (top of dial), increasing clockwise. One full rotation = 24 hours. SwiftUI's native angle system (0 = 3 o'clock) is offset by -pi/2 wherever rendering happens.

---

## Roadmap

These are bigger-picture ideas beyond the current to-do list. Some are practical, some are ambitious, some are "who knows, the possibilities are endless."

### Jetlag Schedule Optimizer
Input a flight itinerary (ideally pulling times automatically). Get day-by-day recommendations for the days before, during, and after travel. Smart assumptions about in-flight meal services. Melatonin timing suggestions. The works.

### Sleep Resources Hub
Curated links to evidence-based sleep products. Temperature and lighting recommendations. A guided setup for making your phone more sleep-friendly (Focus modes, Night Shift, grayscale). Common strategies for better sleep at home.

### White Noise Machine
Built-in ambient sound generator. Fan noise, rain, ocean, forest. Maybe bird sounds for the wake-up alarm -- imagine being gently woken by songbirds instead of that soul-crushing default alarm tone.

### Sleep Journal Analytics
Long-term tracking of sleep/wake times to automatically refine your personal cycle length and fall-asleep duration. Trend charts. "You sleep 12 minutes faster on weekdays" type insights.

### HealthKit Deep Integration
Beyond just reading Apple Watch data -- correlate sleep quality with activity, heart rate, and other health metrics. Surface actionable insights.

---

## Building

1. Open `Moonbeam.xcodeproj` in Xcode 26
2. Select an iPhone 17 series simulator (or a physical device running iOS 26)
3. Build & Run (Cmd+R)

No external dependencies. No CocoaPods, no SPM packages. Just SwiftUI and vibes.

---

## The Science Bit

A typical sleep cycle lasts about 90 minutes and progresses through light sleep, deep sleep, and REM (rapid eye movement) sleep. Most people complete 4--6 cycles per night. Waking at the end of a complete cycle -- rather than in the middle of deep sleep -- is associated with feeling more alert and refreshed.

The 90-minute default is a population average. Individual cycles can range from 75 to 120 minutes, which is why the app lets you customize it. If you track your sleep over time (a feature we're building), you can dial in your personal number.

The 15-minute fall-asleep buffer is based on sleep onset latency research for healthy adults. If you're the type who's out in 5 minutes, or if it takes you 30, adjust it in the profile.

---

<p align="center">
  <sub>Built with SwiftUI, SF Symbols, and an unreasonable amount of trigonometry.</sub><br/>
  <sub>Previously known as "Somnus" in an earlier life.</sub>
</p>
</content>
</invoke>
## Flight schedules and itineraries

Create Plan supports an optional itinerary of up to three connecting flights. Each leg has a flight number and departure-local date. Confirming a schedule fills the first departure and final arrival airports. Manual entry works without a flight-data subscription; enter each airport's local departure/arrival dates and times, including next-day arrivals.

Automatic lookup defaults to the free public FlightStats page, with no account or API key. It reads scheduled gate times and airport time zones from embedded JSON, requires an exact flight-number/departure-date match, and asks the user to confirm the result. Coverage is limited, especially for distant dates, and page changes or access restrictions can break lookup. When a date has no schedule, lookup can offer recent usual times projected onto the selected local dates, explicitly marked as an estimate with the reference date. The user must select those estimated times and verify them against their booking; operation on the chosen day is not guaranteed. Confirmed cancellations are never replaced by an estimate. If lookup remains unavailable, manual entry is available. No scripts are executed and no access restrictions are bypassed.

AeroDataBox remains an optional replacement if a provider subscription is added later:

- For local Debug builds, set `AERODATABOX_API_KEY` in the Xcode Run scheme's environment. This uses AeroDataBox through RapidAPI. Keep the scheme private and never commit credentials.
- For distribution, set the `FlightScheduleProxyURL` Info.plist value to an HTTPS backend URL. The app sends `flight` (normalized flight number) and `date` (`yyyy-MM-dd`, departure-local) query parameters. The backend owns provider credentials and forwards AeroDataBox's JSON flight array. Query its `/flights/number/{flight}/{date}?dateLocalRole=Departure` endpoint. No provider key is included in release builds.
- Documentation: https://doc.aerodatabox.com/rapidapi.html. Lookup handles missing/incomplete schedules, cancellation, authorization errors, and rate limits. Multiple matches require the user to select the correct leg.

A confirmed itinerary adds one travel day to the selected nights. Odd night counts allocate the extra night before departure. Night dates anchor to first departure/final arrival; each flight bar highlights overlap with the travel day's intermediate sleep target, excluding the first hour and final 45 minutes of each leg. Total in-flight sleep is capped at the usual sleep window and excludes layovers. If no useful overlap of at least one hour exists, that leg recommends staying awake. Plan alarms include recommended in-flight sleep windows.

Saved plans retain the itinerary and absolute sleep dates. Changing the night count preserves the itinerary and updates the existing saved plan when saved again.
