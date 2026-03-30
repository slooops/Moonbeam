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
- [ ] **Arc drag gesture polish** -- the arc-drag (moving the whole sleep window) could use smoother snapping and edge-case handling
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