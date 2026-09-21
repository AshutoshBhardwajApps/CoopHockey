# Claude Conventions for CoopHockey

CoopHockey is the app the shared iOS template was extracted *from*
(`~/Documents/Documents - Mac/xcode stuff/iOSAppTemplate/`). Read this before
making changes — it captures patterns the developer cares about, and most of
the pitfalls below were learned here the hard way.

Where this file and the template disagree, **this file wins** — CoopHockey
predates the template and doesn't follow all of its conventions.

For full setup / submission / rejection-recovery playbooks, see the template:
- `iOSAppTemplate/SETUP.md` — new-project end-to-end
- `iOSAppTemplate/PRE_SUBMISSION_CHECKLIST.md` — before every upload
- `iOSAppTemplate/REJECTION_RECOVERY.md` — if Apple rejects

## Architecture

- **SwiftUI app, UIKit AppDelegate adaptor.** AppDelegate handles AdMob
  init, ATT prompt, and audio session setup. SwiftUI handles everything else.
- **Singletons via `@StateObject` in App struct, injected via `@EnvironmentObject`.**
  No DI framework. The App struct creates `SettingsStore.shared`,
  `PurchaseManager.shared`, etc. and hands them down.
- **No `Constants.swift` here.** Unlike the template, CoopHockey keeps its
  per-app values where they're used: ad unit IDs in `AdManager`, the IAP
  product IDs in `SettingsStore`. Don't introduce a `Constants.swift` unless
  you're migrating all of them at once.
- **Flat file layout** — no `Reusable/` directory. `AdManager`,
  `PurchaseManager`, `SettingsStore`, `SFX`, `Haptics` and `AdPresenter` are
  the infrastructure files; treat them as load-bearing.
- **UserDefaults keys are prefixed `h.`** (`h.p1.name`, `h.removeAds`,
  `h.nemesisTrial`). Keep the prefix on anything new.

## Ads (`AdManager`)

- Real ad unit IDs ship in production; `testDeviceIdentifiers` in
  `AppDelegate` makes the developer's device serve test ads.
- `noteRoundCompleted()` after every game/level → drives the ad-pacing counter.
- `presentIfAllowed { shown in ... }` to show an interstitial; the closure
  reports whether one actually presented (so the caller can advance the flow
  either way).
- After an ad dismisses, **wait 0.4s before triggering a SwiftUI sheet** —
  the `.adDidDismiss` notification fires before the ad VC is fully torn down,
  and presenting a sheet too early shows a blank screen.
- **Forced + random promo:** every 8th game guarantees a Remove Ads promo
  (`forcePromoEvery`); random 1-in-12 rolls fill the gaps. `minRoundsBetweenAds`
  is 1, so an interstitial can follow every completed game.
- **Rewarded ads are NOT gated on `adsDisabled`.** Remove Ads buys freedom from
  *forced* interstitials; a rewarded ad is a trade the player opts into, and
  cutting it off would leave paying customers unable to earn NEMESIS games.
- **Debug builds use Google's test rewarded unit**, Release uses the real one.
  A freshly created AdMob unit answers "No ad to show" for hours, which would
  otherwise block testing the earn-a-game flow entirely.

### Which view controller to present from

This matters more than it looks — getting it wrong fails **silently**.

- **Interstitials use `presenterVC()`**, which prefers `AdPresenter`'s fixed
  anchor inside `ContentView`. That's deliberate: interstitials fire at a game
  break with nothing covering the view, and the stable anchor is what lets
  `presentIfAllowed` detect that a sheet is already up and defer instead of
  failing.
- **Anything triggered from inside a sheet or `fullScreenCover` must use
  `topmostPresenterVC()`** — rewarded ads, paywalls, anything launched from a
  presented screen. UIKit refuses to present from a controller that is already
  presenting, and the anchor sits *behind* the cover.
- Symptom when you get this wrong: AdMob reports 100% match rate and **zero
  impressions**. The unit fills every request and displays none. In the
  dashboard it looks almost identical to a no-fill problem, which sends you
  chasing the wrong thing.
- Always log present failures. `didFailToPresentFullScreenContentWithError`
  should `print` loudly — silence there is how this class of bug survives for
  weeks.
- A failed present must **not** be reported to the user as "you closed the ad
  early." They never saw an ad. Report it as unavailable and reload.

## IAP (`PurchaseManager`)

- StoreKit 2 (`Product.products`, `Transaction.currentEntitlements`).
- Two products: Remove Ads (`coophockey.removeads2`) and the NEMESIS unlock.
  The Remove Ads ID is **v2** — the original `coophockey.removeads` got stuck
  in App Store Connect during the 1.3(14) rejection chain and had to be
  replaced. Don't "tidy" it back.
- `loadProducts()` and `restorePurchases()` are called once at app launch
  from the App struct's `.task { ... }`.
- Successful purchase → `SettingsStore.markRemoveAdsPurchased()` →
  `hasRemovedAds = true` propagates everywhere via `@Published`.

## NEMESIS

The adaptive hard-mode opponent, added Aug 2026. Three ways in, modelled by
`SettingsStore.NemesisAccess` (`.owned`, `.trial`, `.credit`, `.locked`):

- **Trial** — 15 minutes of *gameplay* time (`nemesisTrialLimit`). Menus,
  pauses and result screens deliberately don't burn it.
- **Credit** — one rewarded ad earns one full NEMESIS game. A game, not a
  goal; that distinction was a bug fix, don't regress it.
- **Owned** — the IAP.

Notes:
- `nemesisTrialUsed` is deliberately **not** `@Published` — it ticks every
  frame and would thrash SwiftUI. It flushes to UserDefaults every 5s.
- `expireNemesisTrial()` / `resetNemesisTrial()` are `#if DEBUG` only, as is
  the Settings shortcut that calls them. They do not exist in TestFlight.
- Deleting the app **resets** the trial to a full 15 minutes, which makes
  testing the paywall harder, not easier.
- The unlock screen is a `fullScreenCover` — see the presenter rules above
  before showing anything from it.

## Settings (`SettingsStore`)

- All keys are prefixed `h.` to avoid collisions with other apps sharing a
  UserDefaults suite.
- Each `@Published` field has a `didSet { save() }` — no explicit save calls
  needed from view code. The NEMESIS trial counter is the one exception (see
  above).
- Add app-specific fields (player name, difficulty, etc.) to `SettingsStore`
  itself; don't make a second store.

## Haptics + SFX

- Both gated by `SettingsStore.shared.effectsEnabled`.
- Haptics are dispatched to main thread (SpriteKit physics callbacks fire
  off-thread).
- `SFX` synthesizes everything at runtime — no audio files. To add a new
  sound, copy an existing `play*` method and tune the parameters.

## app-ads.txt

- An `app-ads.txt` file lives at the **repo root** and is served via GitHub Pages.
- Enable GitHub Pages (Settings → Pages → main branch, `/` path) so it's reachable at
  `https://ashutoshbhardwajapps.github.io/<repo-name>/app-ads.txt`.
- Set that URL as the **Developer Website** in App Store Connect for the app.
- Content is always: `google.com, pub-2320635595451132, DIRECT, f08c47fec0942fa0`
- The repo must be **public** for GitHub Pages to work on a free plan.

## Versioning

- **`CURRENT_PROJECT_VERSION`** (build number) bumps on every upload.
- **`MARKETING_VERSION`** bumps when you start a new public release train.
- Both live in `project.pbxproj` — find/replace the int across all
  occurrences (typically 2 each, debug + release configs).
- Don't commit a build without bumping the build number, or the archive
  upload fails.

## Common pitfalls

- **`SpriteView` renders black**: pass `options: [.allowsTransparency]`.
- **Mallet/sprite teleports on touch**: capture grab offset in `touchesBegan`,
  apply in `touchesMoved` (`pos = touch + offset`).
- **Edge collisions feel wrong near corners**: use `SKPhysicsBody(edgeChainFrom:)`
  with the same path as the visible border, NOT separate wall rects + corner
  bumpers (the bumper interiors create ghost collision surfaces).
- **Result sheet blank after ad/promo**: 0.4s `asyncAfter` before setting the
  binding to true.
- **Ad unit fills every request but records zero impressions**: you're
  presenting from the wrong view controller. Anything launched from inside a
  sheet or `fullScreenCover` needs `topmostPresenterVC()`, not `AdPresenter`'s
  anchor. See "Which view controller to present from" above.
- **Rewarded ad goes stale**: rewarded ads expire roughly an hour after load.
  Preloading at launch and presenting much later fails. Discard and reload
  anything older than ~50 minutes.
- **DEBUG-only test shortcuts vanish in TestFlight**: `#if DEBUG` helpers
  (expire-a-trial, grant-credits) don't exist in Release builds, so a
  TestFlight tester has to reach that state the long way. If you need to test
  a paywall repeatedly, hide the shortcut behind a five-tap gesture instead of
  gating it on DEBUG.
- **App Store rejects with "ATT permission request not appearing"**: don't
  call `ATTrackingManager.requestTrackingAuthorization` from
  `didFinishLaunchingWithOptions` — iOS silently no-ops requests made before
  the app is in `.active` state. The template's `AppDelegate.swift` defers to
  `UIApplication.didBecomeActiveNotification` + 0.4s delay; keep it that way.

## Style

- Prefer terse comments that explain **why**, not what. Reuse code is
  heavily commented; new code can be lighter.
- `// MARK: -` for major sections.
- 4-space indent (Swift default).
- No emojis in code or commit messages unless the developer asks.
