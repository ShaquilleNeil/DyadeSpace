# DyadeSpace - Setup Checklist (Alex does these himself)

Everything below needs your own accounts/logins, so Athena can't do
it for you. Work top to bottom; each step unlocks the next.

## 1. Create the Firebase project
- [ ] Go to https://console.firebase.google.com and sign in.
- [ ] "Add project" -> name it `dyadespace` -> create it.
      (Google Analytics: optional, can skip.)
- [ ] In the project: **Build > Authentication** -> Get started ->
      Sign-in method -> enable **Email/Password**.
- [ ] **Build > Firestore Database** -> Create database ->
      start in *production mode* (the rules in `firestore.rules`
      get deployed in step 3).
- [ ] **Build > Storage** -> Get started (photo uploads).
- [ ] **Build > Functions**: note - scheduled functions need the
      **Blaze (pay-as-you-go)** plan. Usage at crew size is pennies,
      but the card on file is your call.
- [ ] Register the apps: Project settings -> "Your apps" ->
      add the **Android** app (package id: pick one and keep it,
      e.g. `ca.dyade.dyadespace`) and the **iOS** app (bundle id,
      same style). `flutterfire configure` in step 2 does most of
      this for you if the apps exist.

## 2. Connect the Flutter project
- [ ] Install the Flutter SDK: https://docs.flutter.dev/get-started/install
- [ ] Install the CLIs:
      `npm install -g firebase-tools`
      `dart pub global activate flutterfire_cli`
- [ ] `firebase login`
- [ ] From the `dyadespace-app/` folder:
      `flutterfire configure`  (pick the dyadespace project + both
      platforms; this generates `lib/firebase_options.dart`,
      `google-services.json`, `GoogleService-Info.plist`)
- [ ] `flutter pub get`

## 3. Deploy rules and functions
- [ ] `firebase deploy --only firestore:rules`
- [ ] `cd functions && npm install`
- [ ] `firebase deploy --only functions`
      (deploys the 6 PM America/Toronto end-of-day report and the
      blocked-task alert)

## 4. Bootstrap the FIRST admin (Sam)
Sign-up is invite-only and only an admin can invite - so the very
first invite is created by hand in the console, once:
- [ ] In **Firestore Database > Data**, create a collection
      `invites` with one document (auto-ID) with fields:
      `email` = Sam's email, `role` = `"admin"`,
      `status` = `"pending"`, `invitedBy` = `"bootstrap"`.
- [ ] Run the app (`flutter run`), tap "Create account", and sign
      up with that exact email. The app finds the invite, creates
      his profile with role **admin**, and marks the invite accepted.
- [ ] Sign in as Sam and confirm the manager board opens.
- [ ] From the app's Team (People) screen, Sam invites
      Alex with role **manager**, and the whole crew
      (step 5) - no more console work needed after this.

## 5. First data
- [ ] **Sites:** in Firestore console, add documents to `sites`
      with `name` + `address` for the real buildings (Maple Court,
      Prudhomme 2161, Harborview 1200/5370, Lakeside 109,
      St Antoine 3035, ...). (In-app site editing is a v2 item.)
- [ ] **Crew invites:** as Sam or Alex, open the app ->
      Team (People) -> Invite -> each person's email + role
      (Chris/Dan/Eli/Finn = worker, Drew = delivery).
      Each person installs the app, taps "Create account", uses
      that exact email - the invite sets their role automatically.

## 6. Build & hand out the app
Android (no store):
- [ ] `flutter build apk --release`
- [ ] Firebase Console -> **App Distribution** -> upload
      `build/app/outputs/flutter-apk/app-release.apk`, add the
      crew as testers, release. They get an email, install the
      Firebase App Tester app once, and receive updates from there.
      (Plain APK sideloading also works, but then updates are
      manual re-installs - App Distribution is worth the 5 minutes.)

iOS (TestFlight - Apple Developer account required, $99/yr):
- [ ] Enroll at https://developer.apple.com if not already done.
- [ ] `flutter build ipa --release`
- [ ] Upload the .ipa via the Transporter app (or Xcode) to
      App Store Connect -> DyadeSpace -> TestFlight.
- [ ] Add the crew as internal testers by email; they install via
      Apple's TestFlight app.
- [ ] Calendar note: TestFlight builds expire after **90 days** -
      upload a fresh build before the old one dies.

## 7. Known TODOs after first run
- [ ] **Storage rules:** set Firebase Storage rules so signed-in
      crew can upload to `taskPhotos/` and `runPhotos/` and only
      crew can read them (Firestore rules in this repo do not cover
      Storage - do this in the console before the pilot).
- [ ] **FCM topic subscription:** the Cloud Functions alert the
      `managers` topic. Add the small app-side step: after sign-in,
      if the user is admin/manager, call
      `FirebaseMessaging.instance.subscribeToTopic('managers')`
      (firebase_messaging is already a dependency), and request
      notification permission on iOS.
- [ ] Decide photo retention (spec §11) and set a Storage lifecycle
      rule if you want old photos auto-deleted.
