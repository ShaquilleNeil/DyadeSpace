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

## Features

- **Clock-in with GPS** — one GPS fix per tap, 150 m site radius; outside
  the radius is flagged, not blocked. Auto clock-in optionally checks
  location in the background and records the work route while on the clock
- **My Day** — the worker's tasks for today, grouped by site
- **Board** — kanban by status (To do / In progress / Done / Blocked),
  Overdue pinned on top, filterable by site and person
- **Runs / deliveries** — ordered stop lists with navigation, proof photos,
  and completion tracking
- **Tasks** — assign, reassign, comment, attach photos, mark Done or Blocked
  with a reason; material requests and daily reports with photo support
- **Chat** — crew messaging per site
- **Roles** — admin, manager, worker, delivery, and read-only client.
  Invite-only sign-up: staff accounts are created via an admin-only invite
  flow; clients self-register with read-only project access
- **Reports** — end-of-day report at 6 PM (Cloud Functions), hours export
  (CSV), blocked-task alerts
- **Languages** — EN / FR / ES toggle in the app

## Screenshots

UI previews generated from the app's design tokens ("Midnight" dark theme:
background `#0A0E14`, blue accent `#3D7BFA`, green `#2FBF71` for done).

| My Day | Board | Clock-in | Task |
| --- | --- | --- | --- |
| ![My Day](docs/screenshots/my-day.png) | ![Board](docs/screenshots/board.png) | ![Clock-in](docs/screenshots/clock-in.png) | ![Task](docs/screenshots/tasks.png) |

## Tech stack

- **Flutter** + Riverpod (single codebase, Android-first; iOS project
  files are not in this repo)
- **Firebase Auth** (invite-gated sign-up), **Cloud Firestore**,
  **Cloud Storage** (photos), **Cloud Messaging** (push), **Cloud Functions**
  (6 PM report, blocked-task alerts)
- Role- and project-scoped Firestore rules (see `firestore.rules`)

## Getting started

```bash
# 1. Create a Firebase project in the console (see SETUP_CHECKLIST.md
#    for the full console + device setup, step by step)
# 2. Install Flutter + the FlutterFire CLI, then from this folder:
dart pub global activate flutterfire_cli
flutterfire configure          # generates lib/firebase_options.dart
flutter pub get
# 3. Deploy rules + functions:
firebase deploy --only firestore:rules
firebase deploy --only functions
# 4. Bootstrap the first admin (checklist step 4), invite the crew
#    from the People screen, add the first sites (step 5).
flutter run
```

`lib/firebase_options.dart` is generated on your machine by
`flutterfire configure` — it is git-ignored and **not** in this repo.
The Cloud Functions deploy needs two repo secrets: `FIREBASE_OPTIONS_DART`
and `FIREBASE_SERVICE_ACCOUNT_DYADESPACE` (see `.github/workflows/ci.yml`).

## Project structure

```
lib/
  main.dart               Firebase init + ProviderScope
  app.dart                MaterialApp, auth gate (sign-in vs home)
  l10n/app_strings.dart   EN/FR/ES strings (hand-rolled)
  models/                 app_user, site, task_item, delivery_run,
                          run_stop, day_report (fromFirestore/toMap)
  services/               auth_service (invite-gated sign-up),
                          task_service, photo_service, report_service
  providers/              auth, tasks, sites, locale (Riverpod)
  screens/
    sign_in_screen.dart
    home_shell.dart       bottom nav, tabs chosen by role
    manager/              board, today, by_person, task_editor,
                          people (invites), reports
    worker/               my_day, task_detail, my_history
    delivery/             run_screen (ordered stops)
  widgets/                task_card, status_chip, site_group_header
firestore.rules           role-based rules (see file comments)
functions/                generateDayReport (scheduled 18:00
                          America/Toronto) + notifyBlocked (trigger)
docs/screenshots/      UI preview images
```

## Notes

- The sample sites ("Maple Court", "Harborview 1200") and crew names are
  placeholders — replace them with your own sites and crew when you set
  the app up.
- GPS coordinates in tests are shifted to a fictional grid (45.00 / -73.00)
  so no real site location is exposed.
