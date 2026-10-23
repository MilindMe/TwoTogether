# Two Together

A private SwiftUI iOS app for one fixed pair. Includes a Python/SQLite API, a durable completion outbox, and optional Apple Push Notification service delivery. iOS 17+, Python 3.11+. No third-party app or Python dependencies.

## Open the app

Open `ios/TwoTogether.xcodeproj` in Xcode. The default Debug configuration is for running on an iPhone with a Personal Team: it omits the APNs entitlement and uses the in-app nudge inbox. Select the TwoTogether target, choose your Apple Account's Personal Team under Signing & Capabilities, leave automatic signing enabled, choose the iPhone as the run destination, and use Product > Run. Xcode will create the development profile; do not create one by hand.

Release carries the APNs entitlement and compiles push support. Enabling Push Notifications requires a paid Apple Developer Program team and the capability enabled for the App ID. Use that team when configuring a release/TestFlight build. Supply each friend their own account key and the same HTTPS server address on the welcome screen. Account keys are stored in the device Keychain.

The generic verification build uses code signing off and **cannot be installed on a phone**. Build and Run from Xcode with your Personal Team to create an installable development build (in-app nudges only). A signed build and an actual backend are required for use. No production accounts or credentials have been created in this repository.

## Start a local backend

From this folder:

```sh
python3 backend/server.py --db data/habits.sqlite provision 'Your Name' 'Partner Name'
python3 backend/server.py --db data/habits.sqlite serve
```

Provisioning prints two high-entropy private account keys once. Share each key only with its owner. It cannot add a third person or reprovision an existing database. The database stores key hashes, never the raw keys. Keep the database and its WAL files private and backed up. Start the server with the same database file on subsequent runs.

An iOS simulator can use `http://localhost:8080` when its simulator service is available. Physical devices must use an HTTPS host; localhost on a phone refers to the phone itself. The app rejects other HTTP addresses. Use a reverse proxy to terminate HTTPS rather than exposing the Python server directly.

## Deploy with HTTPS

Deployment files are provided; deployment has not been run here. On a Docker host, point a domain’s DNS to the host and allow ports 80/443. Then:

```sh
cp .env.example .env
# Edit HABITS_DOMAIN in .env.
mkdir -p secrets
docker compose build
docker compose run --rm backend provision 'Your Name' 'Partner Name'
docker compose up -d
```

Caddy manages HTTPS. The API is reachable only through Caddy; its container port is not published. SQLite lives in the persistent `habits` volume. Run exactly one backend replica and one push worker (the worker is part of that process). To back up a running instance, use SQLite’s online backup API rather than copying the active main file without its WAL. Retain the database volume when updating containers.

There is no public signup, admin UI, or user-switching shortcut. Possession of a person’s key grants their account access. A lost key can be replaced administratively by updating that person’s `token_hash` to the SHA-256 hash of a newly generated 32-byte random key; existing sessions will then receive 401. Never send keys in URLs or commit them.

## Enable push

The inbox and nudge limits work without APNs credentials or notification permission. In that case nudges have `in_app` delivery state.

1. Use a paid Apple Developer Program team, and enable Push Notifications for the app’s bundle identifier in your Apple Developer account. In Xcode, add the Push Notifications capability to the target when configuring a push-enabled release.
2. Place your APNs `.p8` signing key at `secrets/apns.p8`, readable by container UID 10001. Do not commit it.
3. Set `APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_TOPIC` (your exact bundle identifier) in `.env`.
4. Set `APNS_SANDBOX=true` for Xcode development installs or `false` for TestFlight/Ad Hoc production installs. This first version uses one environment per backend.
5. Restart the backend and enable nudge notifications in the app’s Nudges tab or Settings.

APNs jobs persist across restarts. Temporary failures retry with backoff up to eight attempts. Invalidated device tokens are removed; failed push delivery leaves the inbox entry available. Push uses a stable APNs ID and collapse ID for retries. APNs delivery itself is best effort. Tokens move to the current signed-in person when registered. Sign-out deregisters the current device first.

Apple references: [registering with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns), [token-based APNs connections](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns).

## Implemented behavior

- Today defaults to your habits. Partner progress is read-only, with an explicit nudge action.
- Two-column widget cards adapt to one column at accessibility text sizes. Checkmarks, text, and symbols distinguish states without relying on color.
- Habit creation, preset icons/colors, selected weekdays, editing, and archiving.
- Names/appearance change immediately. Schedule edits and archives take effect tomorrow; today remains available. Prior schedules are immutable. Multiple edits on the same day replace tomorrow’s pending schedule.
- Weekly rows use Monday–Sunday civil dates, with completed, missed, open today, future, and unscheduled states. Totals include scheduled dates through today and exclude dates before creation and on/after archive.
- Owner corrections for today and yesterday only, enforced by both app and server.
- Optimistic check-ins save atomically to Application Support before the UI accepts them. An ordered durable queue retains desired states and operation IDs across restarts. Server receipts prevent a retried older operation from overwriting a later one.
- Queued dates that have become older than yesterday are rejected with a visible explanation, following the correction-window rule. They are not silently backdated.
- Pending states and retry controls are visible. Partner data refreshes on opening, pull-to-refresh, and every 15 seconds while active. Offline views show the last synced snapshot.
- The fixed pair uses America/Toronto by default. Device travel does not change dates. Civil date arithmetic avoids DST shifts. The server is authoritative for accepted dates; devices should use automatic system time.
- Nudges require an incomplete partner habit scheduled today. Transactional limits enforce one per habit/day and three per sender/day, including concurrent requests. Push opens the relevant habit. The inbox survives push failures or declined permission.

This version uses private provisioned account keys rather than password registration. Two devices editing the same person’s account use the server’s last accepted operation; normal use is one identity per friend.

## API

All endpoints require `Authorization: Bearer <private account key>`. GET `/v1/snapshot` returns the pair’s people, timezone, today, full habit schedule history, completions, and the caller’s sent/received nudges. Successful POSTs return the same snapshot contract.

| POST endpoint | JSON fields |
| --- | --- |
| `/v1/habits` | `id`, `name`, `icon`, `color`, `weekdays` (ISO Monday=1…Sunday=7) |
| `/v1/archive` | `habit` |
| `/v1/completion` | `operation` (stable unique ID), `habit`, `date` (`YYYY-MM-DD`), `completed` (boolean desired state) |
| `/v1/nudge` | `habit` |
| `/v1/read` | `id` (nudge ID; recipient only) |
| `/v1/device` | `token` (APNs token as lowercase hex) |
| `/v1/logout` | `token` (remove device registration) |

Errors return `{"error":"…"}` with an HTTP status. Reusing a completion operation ID with different data returns 409. An exact retry returns current state without reapplying the original change. Successful nudge retries return the existing entry. There is no mutation endpoint for someone else’s completion or a pair’s timezone.

## Verification

```sh
./scripts/verify.sh
```

This runs 18 Python tests, 7 Swift tests, and an unsigned iPhoneOS build. `--disable-sandbox`/`-disable-sandbox` allow compiler subprocesses in restricted development environments; they do not change the app’s sandbox. The Xcode project is checked in; regenerate it after adding source files with `python3 scripts/generate_project.py` (then reselect your signing team).

Automated tests cover authorization, concurrent writes and nudges, retries after restart, undo, correction boundaries, historical schedules, archives, timezone/DST boundaries, HTTP request parsing, push failure handling, and cache reopening. HTTP handler tests use an in-memory transport; no real server socket or live APNs connection was available in this execution environment.

Verified here: all 25 tests pass and an unsigned iPhoneOS build succeeds with Xcode 27.1. Simulator launch, Docker deployment, live APNs, VoiceOver, and two physical devices have **not** been verified. This Mac has no signing identity and the execution sandbox blocks listening ports and simulator services.

## Install and two-week trial

For a private two-person installation, use Xcode device installs or a signed Ad Hoc export for the registered phones. TestFlight is another option, subject to Apple’s distribution requirements; its builds require production APNs. Before sharing:

- Install under each friend’s own key. Verify a third key receives 401.
- Check one habit, confirm partner visibility, undo, then tap rapidly.
- Enable airplane mode, check/undo a habit, force-quit and reopen, reconnect, and confirm the final state on both phones.
- Edit a weekday schedule, archive another habit, and verify prior weekly totals stay unchanged across midnight in Toronto.
- Correct today/yesterday and confirm older cells are read-only.
- Nudge a partner, retry, reach the daily cap, and try completed/rest-day habits. Test notification opening from a terminated app, and repeat with permission denied.
- Use the largest text size and VoiceOver to create, find, check, and undo a habit.

Use it for 14 days. At the end, ask both people whether check-ins felt quick, partner progress stayed reliable, nudges felt encouraging, and shared visibility helped them follow through. That outcome requires the actual trial and cannot be established by automated tests.
