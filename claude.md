# Curious Places (iOS)

A native SwiftUI rewrite of **Lantern**, an Expo/React Native app for discovering folklore, legends, and other unusual places in London. The app has a map of places, place detail pages with audio narration, a compass "hunt" mode that guides you to a place, curated tours, user lists, and check-ins with badges.

## Port status

Full analysis of the Expo app is in `docs/migration/01-inventory.md`. Read §1 "Decisions so far" before changing data access.

- **Data access:** the app uses the Supabase **anon key only**, never the service-role key, and never calls the Replit server. Missing RLS policies are drafted in `supabase/proposed/` (not yet applied).
- **Milestones:**
  1. Foundation and Explore map ✅
  2. Auth: Apple, Google, email and guest, plus the profile and language sync to `profiles.preferred_language` ✅ (code done; needs the dashboard setup below)
  3. Full place detail: facts, audio, votes and issue reports. **Narration playback is done:** `Services/NarrationService.swift` and `NarrationPlayer.swift`, plus `Features/PlaceDetail/NarrationView.swift`. It autoplays and streams from **public** audio buckets (`supabase/proposed/04`), trying the user's language, then English, then the legacy `audio_overviews_*` buckets. Not yet built: generating missing audio (needs a TTS Edge Function), fact audio, facts, votes and reports.
  4. Compass hunt, check-ins and badges
  5. Lists and tours
  6. Admin (undecided)

**Auth.** Code is in `Services/SessionStore.swift` and `Features/Auth/`.
- **Google:** OAuth in a web sheet, returning to `curiousplaces://auth/callback`.
- **Apple:** native, using a nonce.
- **Email:** password sign-in. Confirmation links come back through the same URL.
- **Guest:** guest mode is remembered across launches (`isGuest` in UserDefaults).
- **Admin:** a user is admin if `profiles.admin_flag` is set, or if their *verified* email is nick.jewell@gmail.com, whichever way they signed in. This rule lives in `AdminAccess` (Models/Profile.swift) and in `public.is_admin()` in `supabase/proposed/03`. A Hide-My-Email Apple account needs `admin_flag` set by hand.

**Sign in with Apple is switched off** (`Config.isSignInWithAppleEnabled = false`, and no `CODE_SIGN_ENTITLEMENTS`). The current team (Q7Q64466N4) is a free Personal Team, and those can't use that capability. To turn it on:
1. Join the Apple Developer Program and select that team.
2. Set `CODE_SIGN_ENTITLEMENTS = Curious-Places.entitlements` on the app target. The file is already at the repo root.
3. Flip the flag to `true`.
4. Do step 1 below, and register the capability: open the target's Signing & Capabilities tab once with the paid team selected.

This has to be done before release: App Store guideline 4.8 requires Sign in with Apple when Google sign-in is offered.

**Setup needed for milestone 2:**
1. Auth → Providers → Apple (only once Sign in with Apple is on): enable it, and add `jewell.Curious-Places` to Client IDs.
2. Auth → URL Configuration → Redirect URLs: add `curiousplaces://auth/callback`.
3. Apply `supabase/proposed/03_account_and_admin.sql`. Without it, Delete Account shows an error.

Email confirmation links only work when tapped on the same device that signed up, because the PKCE verifier is stored there.

**Release blocker:** deleting an account that signed in with Apple must also revoke its Apple tokens. That needs an Edge Function, which isn't built yet.

Code layout under `Curious Places/`: `App/`, `Models/`, `Services/`, `Features/<Feature>/`, `Theme/`. The project uses folder-synced groups, so new files are picked up without editing the project file. Default actor isolation is MainActor, so Codable models are marked `nonisolated`.

## Reference app (the Expo original)

- Local clone: `../curious-places-replit` (branch `replit-backup`)
- GitHub: https://github.com/NickJewell/curious-places-replit
- Treat it as read-only. Port behaviour from it and don't edit it.

Where to look:

| Topic | Expo source |
|---|---|
| Overview and architecture | `replit.md`, `design_guidelines.md` |
| Places and map queries | `client/lib/supabase.ts` |
| Lists | `client/lib/lists.ts` |
| Check-ins and badges | `client/lib/checkins.ts` |
| Screens | `client/screens/*.tsx` (skip the `.web.tsx` and `Admin*` screens) |
| Global state (auth, hunt, tour, theme) | `client/contexts/*.tsx` |
| Colours and map styling | `client/constants/theme.ts`, `client/constants/mapStyle.ts` |
| DB tables added over time | `supabase/migrations/*.sql` |

**`replit.md` is partly out of date.** It describes a Drizzle `locations` table, but the client reads a Supabase `places` table. When the two disagree, trust `client/lib/*.ts` over `replit.md` and `shared/schema.ts`.

### How the Expo app gets data

- **Directly from Supabase:** `places`, `lists`, `list_items`, `checkins`, `badges`, `user_badges`, and the `get_user_progress` RPC.
- **Through the Express server on Replit (`server/routes.ts`):** `/api/map/viewport` (places in the current map area) and `/api/tours`.

Before porting the map or tours, decide whether the iOS app should call that server or query Supabase directly.

## Project setup

- Xcode project: `Curious Places.xcodeproj`. Bundle ID: `jewell.Curious-Places`.
- Dependency: `supabase-swift` (Swift Package Manager). The shared client is the global `supabase` in `Curious Places/Config.swift`.
- Secrets: copy `Secrets.example.xcconfig` to `Secrets.xcconfig` and fill in `SUPABASE_HOST` and `SUPABASE_ANON_KEY`. `Curious-Places-Info.plist` passes them into the Info dictionary, and `Config` reads them at launch. If either is missing, the app crashes on purpose.
- **Never commit `Secrets.xcconfig`.** It's in `.gitignore`, but it was tracked before that entry was added. Untrack it with `git rm --cached Secrets.xcconfig` if that hasn't been done yet.

## Porting notes

- Map: the Expo app uses Google Maps with custom light and dark styles. MapKit is the natural iOS replacement, so map styling will need rethinking.
- Compass hunt: magnetometer heading with a circular-mean low-pass filter, arrival detected within 10 m, plus haptics. On iOS this maps to `CLLocationManager` heading updates.
- Theme: a warm cream light palette (`#F5F2ED`) and a deep navy dark palette (`#0A0E14`) with gold accents. The exact values are in `theme.ts`.
- Audio narration autoplays when a place detail page opens.
