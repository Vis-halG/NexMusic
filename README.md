# nexMusic

Premium Flutter music app connected to its own Firebase project. The custom
Dart source stays compact: four handwritten files plus FlutterFire's generated
configuration file.

## Firebase project

- Account: `vishalgupta25989@gmail.com`
- Project name: `nexMusic`
- Project ID: `nexmusic-25989`
- Android: `com.thenex.nex_music`
- iOS: `com.thenex.nexMusic`
- Web app is registered

`lib/firebase_options.dart` and `android/app/google-services.json` were generated
for this project. Do not replace them with files from NexConnect or
TheNexSociety.

## Firebase features

- Google login through Firebase Authentication
- Private folders and saved-link metadata in Cloud Firestore
- User-owned trimmed audio in Firebase Storage
- Original user-owned audio/video upload, permanent delete and per-device
  offline download inside nexMusic's private app folder
- User-scoped Firestore and Storage security rules
- Shared online URLs are saved as links; nexMusic does not download or extract
  media from third-party online services
- Local media owned by the user can be trimmed/extracted on Android and uploaded

Deploy the included rules with the second account:

```powershell
firebase deploy --only firestore:rules,storage --project nexmusic-25989 `
  --account vishalgupta25989@gmail.com
```

Firebase Storage requires the project to be on the Blaze plan. Firebase still
includes its no-cost Storage quota, but billing must be attached before the
bucket can be provisioned or audio uploads can work.

## Run

```powershell
flutter run -d chrome
flutter build apk --debug
```

## Source layout

```text
lib/main.dart              Firebase bootstrap and theme
lib/firebase_options.dart  generated FlutterFire configuration
lib/music_data.dart        models and demo catalogue
lib/music_controller.dart  playback, Auth, Firestore and Storage
lib/music_ui.dart          all screens and shared components
android/.../MainActivity.kt  owned-media trim/extract channel
firestore.rules            private metadata rules
storage.rules              private audio/video rules (100 MB per file)
```
