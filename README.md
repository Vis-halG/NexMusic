# nexMusic

Minimal Flutter music app for a small group. Signed-in listeners upload songs
and videos into shared categories, many files at a time, and every upload is
playable by everyone who is signed in. Files are stored on Cloudinary; Firebase
(Spark plan) handles login and the shared listing. The custom Dart source stays
compact: five handwritten files plus FlutterFire's generated configuration file.

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

## Cloudinary

- Cloud name: `j0fu6gju`
- Unsigned upload preset: `nexmusic_unsigned` (folder `nexmusic`, overwrite off)

Both values live in `lib/music_controller.dart` and can be overridden with
`--dart-define=CLOUDINARY_CLOUD_NAME=…` and
`--dart-define=CLOUDINARY_UPLOAD_PRESET=…`. They are not secrets. Never put the
Cloudinary API key or API secret in the app.

The preset has no format or size restriction yet, so anyone who extracts it from
the APK could upload to the account. The app itself only sends audio or video
under 100 MB. Deleting a song in the app removes it from everyone's list; the
file stays on Cloudinary until it is removed from the Media Library.

## Features

- Google login through Firebase Authentication. Nothing is visible signed out.
- Shared catalogue: any signed-in user creates categories and uploads files up
  to 100 MB each.
  - Audio: mp3, m4a, aac, wav, flac, ogg, oga, opus, amr, 3ga, mka, aiff and
    aif.
  - Video: mp4, m4v, mov, webm, mkv, 3gp, 3g2, avi, flv, wmv, mpg, mpeg, ts,
    mts, m2ts, ogv and mxf.
  - Phones cannot play AIFF, AVI, FLV, WMV, MPEG, TS, OGV, MXF and 3G2
    reliably, so their saved link asks Cloudinary for an MP3 or MP4 copy. The
    first play of a large converted video can take a while, and conversions
    use the Cloudinary plan's transformation quota.
  - WMA is not accepted because Cloudinary does not take it.
- Multi-select upload: pick many files, choose one category, upload three at a
  time with per-file progress, retry for failures, and skipping of files that
  are already in the catalogue (same title and size). A running batch can be
  paused, resumed or cancelled from the upload screen; a song that was halfway
  starts again from the beginning on resume, because Cloudinary takes each
  file in one request, and a song already sent to Cloudinary is left to finish
  so it is never stranded without its catalogue entry. On Android the chooser
  only keeps a link to each file; a file is copied into the cache just while
  it uploads, so choosing hundreds of songs does not fill the phone.
- A category must be picked before uploading. Anyone signed in can later
  rename any upload, move it to another category, or delete it. Songs show
  their category, never the uploader's name.
- Categories are added, renamed and deleted from the "Edit" button next to the
  category pills on the home, upload and song editor screens. Only a
  category's creator can rename or delete it. Deleting a category that has
  songs asks first, then removes the category and all its songs for everyone
  (the files stay on Cloudinary).
- Liked and recently played songs, stored on the device.
- Music keeps playing in the background, with play/pause/next controls on the
  lock screen and in the notification bar.
- Notifications: uploads and offline downloads show progress, and the other
  phones are notified when someone uploads, edits, moves or deletes a song or
  category (see "Activity notifications"). Profile → Activity notifications
  turns them off on one phone.
- Home screen widgets:
  - Music players, each a different design and size: Now playing (4×1),
    Mini player (2×1), Square player (2×2), Big player (4×2, shows what plays
    next), Tall player (2×3) and Play button (1×1).
  - Clocks, each a different design and size: Big clock (4×2), Analog clock
    (2×2), Clock and music (4×1, time beside the playing song), Stacked clock
    (2×3) and Date pill (3×1). They keep time on their own and open the Clock
    app when tapped.
  - Quick actions (upload, search, browser, downloads).
  - Latest uploads, Recently played and Liked songs.
- Any song or video can be downloaded from its ⋮ menu and then plays from the
  phone without internet (Profile → Downloads). A download is removed when
  its uploader deletes the song.
- Sharing a YouTube link to nexMusic opens the upload screen straight away.
  Out of sight behind the app, the in-app browser searches "youtube to mp3",
  opens the top ordinary result (Google's adverts are skipped) and walks the
  converter through Paste, Convert and Download, while the upload screen shows
  how far it has got. The title and category can be chosen meanwhile, and
  pressing Upload returns to the home screen at once: the hidden browser's
  progress ("Converting…", "Downloading 40%") shows where upload progress
  does, and the song uploads the moment its audio arrives, waiting its turn if
  another batch is still uploading. If the audio cannot be fetched after the
  screen has closed, a message says so. Leaving without pressing Upload stops
  the hidden browser. Each step is tried a few times, and the whole fetch gives up
  after three minutes; the upload screen then offers "Try again", or "Open
  browser" to finish the converter by hand. The hidden browser fills the
  screen underneath the app's pages, because converter pages only lay out
  their buttons at a real size. It presses the site's own buttons, trying
  several labels ("Convert", "Start", "Go", "OK", …). Reading the page only
  ever carries a step from Converting to Download, and a file is fetched once
  per page. Links that would take the page off the converter's own domain are
  blocked, because adverts on these sites wear the same words as the real
  button; if the file has just been asked for, the download is asked for
  again. This only works as well as the site does: some converters answer
  every download press with an advert (ytmp3.cc did when this was written),
  so no file arrives from them. The browser has no back, forward or shortcut
  buttons. Other shared links open the "Save link" screen. nexMusic never
  contacts YouTube itself.
- A song or video downloaded inside the in-app browser is saved to the app
  cache and opens the upload screen with the file ready; a category still has
  to be chosen. Direct file links are captured; downloads a page builds in
  JavaScript (`blob:` links) are not.
- Any audio file can be trimmed before uploading (Android): play it, tap
  "Start here" and "End here" or drag the handles, then "Use this part". MP3
  stays MP3 and AAC/M4A is copied into M4A without re-encoding. Other formats
  the phone can decode (FLAC, WAV, Ogg, Opus, AMR, …) are converted to AAC in
  M4A, or saved as WAV on phones whose AAC encoder refuses to start (the
  Android 15 emulator's does). The original is kept so the trim can be redone
  or undone.
- Private library: saved links, in-app browser and Android share-sheet import.
  Keeping your own files privately (trim or original) and offline download use
  Firebase Storage, which needs the Blaze plan. Streaming links (`.m3u8`,
  `.mpd`, `rtsp://`) cannot be played.

### Keeping Firestore inside the free quota

The song listing is cached on each device (`catalog_cache_v1.json`) and only
documents whose `updatedAt` is newer than the last sync are read, so opening the
app does not re-read the whole catalogue. Songs are soft-deleted
(`deleted: true`) so other phones can sync removals the same way.

## Data model

| Location | Contents | Who can write |
| --- | --- | --- |
| Firestore `categories/{id}` | `name`, `ownerUid`, `createdAt` | any signed-in user creates; creator renames/deletes |
| Firestore `songs/{id}` | `title`, `kind`, `categoryId`, `url`, `publicId`, `sizeBytes`, `durationMs`, `ownerUid`, `ownerName`, `createdAt`, `updatedAt`, `deleted` | any signed-in user creates their own; anyone signed in can change `title`, `categoryId`, `deleted`, `updatedAt` |
| Firestore `pushTokens/{id}` | `uid`, `token`, `updatedAt` | that phone's user; read by the push Worker |
| Cloudinary `nexmusic/…` | public upload files | unsigned preset |
| Firestore `users/{uid}/folders`, `users/{uid}/media` | private library metadata | that user only |
| Storage `users/{uid}/…` | private library files (Blaze only) | that user only |

Songs and categories are readable by every signed-in user.

Publish `firestore.rules` in the Firebase console (Firestore Database → Rules),
or deploy with:

```powershell
firebase deploy --only firestore:rules --project nexmusic-25989 `
  --account vishalgupta25989@gmail.com
```

## Activity notifications

Firebase's free plan cannot run server code, so a free Cloudflare Worker
(`push_worker/worker.js`) sends the notifications:

1. Each signed-in phone saves its Firebase Cloud Messaging token in
   `pushTokens`.
2. After an upload, edit, move or delete, the app posts a title and text to
   the Worker with the user's Firebase ID token.
3. The Worker checks the token and sends the notification to every other
   phone, and forgets tokens of phones that uninstalled the app.

Setup:

1. Firebase console → Project settings → Service accounts → Generate new
   private key. Keep the JSON file private; it never goes into the app.
2. Cloudflare dashboard → Workers & Pages → Create → Worker. Replace the code
   with `push_worker/worker.js` and deploy.
3. Worker → Settings → Variables and Secrets → add a secret named
   `SERVICE_ACCOUNT` whose value is the whole JSON file.
4. Put the Worker URL in `pushWorkerUrl` in `lib/phone_services.dart` (or pass
   `--dart-define=PUSH_WORKER_URL=…`) and rebuild the APK. It is currently
   `https://nexmusic-push.vishalgupta25989.workers.dev`.

A phone is never notified about its own user's actions, so testing delivery
needs two phones signed in with different Google accounts.

## Run on the Android emulator

1. Turn on Windows Developer Mode (`start ms-settings:developers`). Flutter
   needs symlinks to build plugins.
2. Register the debug keystore's SHA-1 and SHA-256 on the Android app in
   Firebase project settings, otherwise Google login fails with
   `[16] Account reauth failed`:

   ```powershell
   keytool -list -v -keystore $env:USERPROFILE\.android\debug.keystore -storepass android
   ```

3. Use a Google Play system image with a Google account added. For an AVD made
   with `avdmanager`, set `hw.keyboard = yes` and `PlayStore.enabled = yes` in
   its `config.ini` so the laptop keyboard works, then cold boot it.

```powershell
flutter emulators --launch NexMusic_API_35
flutter run -d emulator-5554
```

Other targets: `flutter run -d chrome`.

## Build the APK to share

Test phones are short on storage, so the shared APK is kept as small as
possible:

```powershell
powershell -ExecutionPolicy Bypass -File tool\small_apk\build.ps1
```

It writes `build\nexMusic-arm64.apk`, which installs on arm64 phones only. The
script builds an obfuscated `android-arm64` release and recompresses the APK
with zopfli (Node.js is needed; `@gfx/zopfli` is installed on the first run).
It then runs `zipalign` and signs with the same debug key as the release build,
so the APK installs over earlier test builds. Keep `build\symbols` to decode
crash stack traces from that build.

`android/app/build.gradle.kts` does the rest:

- Native libraries are compressed inside the APK. Android unpacks them on
  install, so the installed app is larger than the APK.
- Plugin libraries for other ABIs, `.proto` sources, Kotlin reflection metadata
  and non-English library translations are left out.
- ExoPlayer's DASH, HLS, RTSP and SmoothStreaming modules are left out, so the
  app refuses `.m3u8`, `.mpd` and `rtsp://` links before playback.

`android/app/src/main/res/raw/keep.xml` keeps resources that libraries look
up by name, so resource shrinking does not remove them. Without it, Google
sign-in on a fresh install fails with "serverClientId must be provided on
Android", because `default_web_client_id` is stripped.

reCAPTCHA cannot be left out, because Firebase Auth loads it when it starts.
The Poppins fonts are subset to Latin characters, so Devanagari text uses the
system font, and the PNGs use 256-colour palettes. Check the APK size again
after adding a package or asset.

## Source layout

```text
lib/main.dart              Firebase bootstrap and the monochrome + violet theme
lib/firebase_options.dart  generated FlutterFire configuration
lib/music_data.dart        category, song, upload and private-library models
lib/music_controller.dart  playback, Auth, catalogue sync, Cloudinary uploads
lib/music_ui.dart          all screens and shared components
lib/phone_services.dart    lock screen controls, widgets, notifications, push
android/.../MainActivity.kt  trim/extract channel and widget launch actions
android/.../NexPhone.kt    progress and activity notifications
android/.../NexWidgets.kt  home screen widgets
push_worker/worker.js      Cloudflare Worker that sends activity notifications
tool/small_apk/            builds the small APK to share
firestore.rules            catalogue and private metadata rules
storage.rules              private library file rules (Blaze only)
```
