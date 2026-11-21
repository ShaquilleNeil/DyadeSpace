# DyadeSpace

Crew task app for a renovation company: one shared board, tasks by status,
Overdue pinned on top, Today grouped by site, and a By-person view. Workers
see only their day, mark tasks Done with a photo, or Blocked with a reason.
Delivery crew get their runs as ordered stop lists, and managers get an
end-of-day report at 6 PM.

> **Demo data:** everything in this repo is fictional sample data — the
> sites are "Maple Court" and "Harborview 1200", and the crew are Alex,
> Sam, Chris, Dan, Eli, Finn, and Drew. No real client names, site
> addresses, phone numbers, or job details are included.

## Where things live

- **`flutter_app/`** — the current app (v2): Flutter + Firebase crew
  management app. See [`flutter_app/README.md`](flutter_app/README.md)
  for features, setup, and project structure.
- **`app/`** — the original Android app (Kotlin + Jetpack Compose,
  Supabase), kept for history. It is no longer developed.
- **`app.zip`** — an archived build of the original app, kept for history.

## Screenshots

UI previews generated from the app's design tokens ("Midnight" dark theme:
background `#0A0E14`, blue accent `#3D7BFA`, green `#2FBF71` for done).

| My Day | Board | Clock-in | Task |
| --- | --- | --- | --- |
| ![My Day](flutter_app/docs/screenshots/my-day.png) | ![Board](flutter_app/docs/screenshots/board.png) | ![Clock-in](flutter_app/docs/screenshots/clock-in.png) | ![Task](flutter_app/docs/screenshots/tasks.png) |

## Quick start

```bash
cd flutter_app
flutter pub get
dart pub global activate flutterfire_cli
flutterfire configure          # generates lib/firebase_options.dart
flutter run
```

Full setup (Firebase console, rules + functions deploy, first admin) is in
[`flutter_app/SETUP_CHECKLIST.md`](flutter_app/SETUP_CHECKLIST.md).

## Tech stack

- **Flutter** + Riverpod, **Firebase Auth** (invite-gated sign-up),
  **Cloud Firestore**, **Cloud Storage**, **Cloud Messaging**,
  **Cloud Functions** (6 PM report, blocked-task alerts)
- Role- and project-scoped Firestore rules
- EN / FR / ES in-app language toggle
