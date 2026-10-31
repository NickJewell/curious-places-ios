# Milestone 6: Walking directions

**Status:** built 2026-10-31. It passes the unit tests and a simulated walk; the real walk on a device is still to do.

## Outcome

**How the build differs from the plan below:**
- **No `routeStatus` enum.** "No route" is simply `walkingRoute == nil`, and the map page falls back to the straight-line pill.
- **The request isn't cancelled when the compass is put away.** The route is still wanted on return, so cancelling would only spend another request.
- **Any failure backs off for 60 s,** not just throttling. That also covers no network and no route.
- **The remaining distance includes the dashed last leg,** so it doesn't stop short of the place.
- **The user's dot is drawn above the target,** so it stays visible up close.
- **VoiceOver reads the same whole minutes as the pill** (`RouteGeometry.walkingMinutes`).

**Simulator walk, 2026-10-31.** The user started at Liverpool Street, heading for Aldgate East on the Jack the Ripper tour.
- The route appeared within seconds and read "18 min · 1.2 km".
- It counted down while walking: "14 min · 979 m".
- It rerouted once after the user strayed north, to "13 min · 899 m", with the line starting from the new position.
- At 32 m it read "32 m · E · Use the compass".
- "Open in Maps" opened Apple Maps' walking directions to Aldgate East. The hunt was still running on return.

**Not yet checked:**
- A real walk on a device, including how throttling behaves over a long hunt.
- The offline fallback, which the simulator can't easily simulate.

**Possible follow-up:** trim the part of the line already walked. `RouteGeometry` already finds the nearest segment, so the remaining path could be drawn from there.

## Why

The hunt's map page draws a straight line from the user to the target, through buildings. MapKit gives us walking directions at no cost: no API key, no billing and no quota beyond per-device throttling. Expo used Google Maps and never had routes.

## What we're building

1. **A walking route on the hunt map page.** A gold line follows the streets from the user to the target, under the pulse rings.
2. **Walking time and distance in the map page's pill**, e.g. "12 min · 850 m", replacing the straight-line "850 m · NE" while a route is available.
3. **An "Open in Maps" button in the hunt header.** It hands off to Apple Maps for spoken turn-by-turn walking directions.

**Unchanged:**
- **The compass page.** It's for the final approach, where routes stop helping.
- **Arrival and check-in.** These keep using the straight-line distance and the `HuntMath` thresholds (10 m, 40 m, 20 m accuracy). Routes never decide arrival.
- **Units.** The hunt stays metric, through `HuntMath.formattedDistance`.

## Out of scope

| Item | Why it's out |
|---|---|
| Real walking legs on tour maps (`TourRouteMap`) | A 17-stop tour needs 16 requests. Planned as milestone 6b below. |
| Turn-by-turn guidance or voice inside the app | MapKit provides the route and step text only. "Open in Maps" covers spoken guidance. |
| A step-by-step instruction list | Easy to add later from `MKRoute.steps`, but not needed for a short walk. |
| The route on the Explore map while the compass is put away | The hunt's sensors stop when the compass closes (`HuntStore`), so the line would go stale. |
| Background navigation | The app has no background location mode, and adding one is a separate decision. |

## Design

### Where the route lives

The route lives in **`HuntModel`**, next to `location` and `progress`:
- `HuntStore` already creates a fresh `HuntModel` for each target and each route stop, so routes reset per stop for free.
- The model survives putting the compass away, so reopening it doesn't request the route again.

```swift
// HuntModel
private(set) var walkingRoute: MKRoute?
private(set) var routeStatus = RouteStatus.idle   // idle, loading, ready, unavailable
```

### New service: `Services/DirectionsService.swift`

This is a thin wrapper, injectable like the other services so it can be swapped in tests:

```swift
final class DirectionsService {
    func walkingRoute(from start: CLLocationCoordinate2D, to place: Place) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        guard let route = try await MKDirections(request: request).calculate().routes.first else {
            throw MKError(.directionsNotFound)
        }
        return route
    }
}
```

Use `MKMapItem(location:address:)`. The placemark initialiser is the pre-iOS 26 API.

### When to ask for a route

Apple throttles directions requests per device (`MKError.loadingThrottled`) and doesn't publish the limit. Requests must be driven by events, not made on every fix.

Put the decision in a pure function, `RoutePolicy.shouldRequest(...)` in `HuntMath.swift` or a sibling file, so it can be unit-tested:

| Rule | Value (tunable) |
|---|---|
| First request | On the first fix accurate to **100 m** or better. Routing needs less precision than check-in. |
| Don't route near the target | Under **75 m** straight-line distance, show the straight-line pill and point to the compass. |
| Reroute when off the route | The user is more than **30 m** from the route line, on a fix accurate to 20 m or better. |
| Minimum gap between requests | **20 s** |
| Cap per hunt stop | **15** requests, then keep the last route |
| After `loadingThrottled` | Keep the last route and don't retry for **60 s** |
| After `directionsNotFound` or no network | `routeStatus = .unavailable`. The map page falls back to today's straight-line view, silently. The hunt is never blocked. |

### Remaining distance and time without new requests

Between requests, work out progress locally. Project the user onto the route's polyline (`route.polyline.points()`, using `MKMapPoint` geometry) to get:
- **The off-route distance**, which feeds the reroute rule.
- **The remaining distance** along the line, from the nearest point to the end.
- **The remaining time**: remaining distance ÷ the route's own pace (`route.distance / route.expectedTravelTime`).

Put this in a pure `RouteGeometry` helper with unit tests. It's the only non-trivial maths in the milestone.

### Hunt map page (`HuntMapView`)

- `MapPolyline(route).stroke(Theme.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))`, drawn before the annotations so it sits under the user dot and the rings.
- **A dashed "last leg".** Walking routes end at the nearest point on a path, which can be 20–50 m from a plaque in a churchyard. Draw a dashed line from `route.polyline`'s last point to the target, `StrokeStyle(lineWidth: 3, dash: [4, 6])` at gold 60%, so the gap reads as "find it from here".
- **Pill text:**
  - Route ready: "12 min · 850 m".
  - Otherwise: today's "850 m · NE".
  - Under 75 m: "60 m · NE · use the compass".
  - Format the time with `Duration` (`.units(allowed: [.hours, .minutes], width: .abbreviated)`); check the output at build time.
- **Framing.** When the first route arrives, fit the user, the target and the route's `polyline.boundingMapRect` once, as `frameUserAndTarget()` does now. Don't move the camera after the user has panned.
- **Loading.** Leave the pill on the straight-line text until the route arrives. Don't show a spinner on a map that's already useful.

### "Open in Maps" (`HuntView` header)

The header's right-hand slot is an empty 44 × 44 spacer (`Color.clear.frame(width: 44, height: 44)`). Put the button there, with the icon `arrow.triangle.turn.up.right.diamond` and the accessibility label "Walking directions in Maps".

```swift
let item = MKMapItem(location: CLLocation(latitude: target.latitude, longitude: target.longitude), address: nil)
item.name = target.name
item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
```

The hunt carries on. When the user comes back, `HuntModel` resumes location updates through the existing `onAppear`/`start()`.

No Maps capability or entitlement is needed. That capability is for apps that *provide* routes to Maps.

### Accessibility

- The pill's text goes into the map page's accessibility label, e.g. "12 minutes' walk, 850 metres".
- The route line is decorative to VoiceOver. The compass page's summary already says the direction.

## Work, in order

1. **`RouteGeometry` and `RoutePolicy`** as pure, `nonisolated` types, with tests in `Curious_PlacesTests.swift`:
   - the off-route distance for points on, beside and past the line
   - the remaining distance at the start, middle and end
   - each policy rule: first fix, accuracy gate, 75 m cut-off, 20 s gap, cap, throttle back-off
2. **`DirectionsService`**, injected into `HuntModel` with a default, like `NarrationService`.
3. **`HuntModel`:** route state, requests driven from `apply(_ location:)` through `RoutePolicy`, and cancelling the in-flight task in `stop()`.
4. **`HuntMapView`:** the polyline, the dashed last leg, the pill text and the one-time framing.
5. **`HuntView` header:** the "Open in Maps" button.
6. **CLAUDE.md:** mark milestone 6 done, with the rules from the table above.

## How to test

- **Unit tests:** steps 1 and 2.
- **Simulator walk:** `xcrun simctl location <device> start --speed=1.4 <lat,lon> <lat,lon> …` replays a walk at walking pace. Script a walk from St Paul's towards a target that turns off the route, and check:
  - the first route appears
  - the remaining time and distance count down without new requests
  - leaving the route by more than 30 m triggers exactly one reroute
  - under 75 m the pill switches to the compass hint
- **Fallbacks:**
  - In flight mode, the map page looks exactly as it does today.
  - For a target inside a park, the dashed last leg shows.
- **Device:** one real walk in the City, to check the route line against the street and the throttling behaviour over a 15-minute hunt.

## Done when

- [x] Starting a hunt shows a walking route within a few seconds of the first fix, in light and dark mode. (The hunt is always dark.)
- [x] The pill shows the walking time and distance, which count down as you walk.
- [x] Going off the route reroutes, never more than once per 20 s and never more than 15 times per stop. (Seen in the simulator; the limits are unit-tested.)
- [ ] No route, no network or throttling silently falls back to the straight-line view. (This is in the code, but not tested offline.)
- [x] "Open in Maps" opens walking directions to the place, and the hunt is still running on return.
- [x] Arrival and check-in behave exactly as before, using the straight-line distance. ("Sign In to Check In" appeared at 32 m.)
- [x] All tests pass.

## Milestone 6b (later): tour legs

- **Real walking legs on `TourRouteMap`.** Fetch the legs one after another (not in parallel), cache them in memory per tour id for the session, and fall back to straight segments for any leg that fails. The legs add up to a true total walking time, which can be shown next to `tour_length`.
- **"Open tour in Maps".** Apple's unified Maps URLs take a `mode=walking` directions link with several `waypoint` parameters. That could hand a whole tour to Apple Maps in one link. Check which iOS version added unified URLs, and how many waypoints Maps accepts, before relying on it.
