# Reference APKs and nexApp integration

Inspected locally on 2026-09-25 using Android `aapt`, ZIP inventory, manifest,
bundled JSON configuration and DEX inspection. Reference APKs and extracted
third-party assets are excluded from Git; neither application was repackaged.

| File | Verified identity | Finding |
| --- | --- | --- |
| `base.apk` | `com.novexa.spicetify`, version `1.0.0` (1), 14,430,877 bytes | Flutter base package with assets and Android glue; no `libapp.so`, kernel snapshot or provider bundle. The architecture split containing compiled Dart code was not supplied. Its exact provider implementation and recommendation algorithm cannot be recovered from this file alone. |
| `movie.apk` | `com.community.oneroom`, version `4.0.02.0831.03` (50020126), 65,055,505 bytes | MovieBox. `assets/appTab.json` describes Trending, Movie, TV and Anime tabs and references `aoneroom.com` artwork. Recommendations/catalogue are service data, not a bundled local recommendation model. |

SHA-256:

```text
base.apk  C283FFB5E846ACA01CF5D6613390C38739F99C38E8C573A7A727B33C79DA25C3
movie.apk D910CA7A01BF99503AB8FC7CC4F5DF3F7B9B494BBB0373F44C6BE44A796AE08F
```

## Implementation

- Stream interleaves JioSaavn and YouTube Music results. Same-source IDs and
  matching title/artist recordings are de-duplicated; video versions remain
  separate. Original provider IDs are retained for playback and offline files.
- Quick Picks uses recent listening and both providers' song radios. Similar
  recommendations map the seed into each catalogue before requesting radio.
  Cold start uses both providers' featured tracks. Requests have independent
  failure handling, bounded caching and stale-response protection.
- JioSaavn radio uses `webradio.createEntityStation` and `webradio.getSong` with
  `ctx=android`. YouTube uses Music `next` radio and genuine continuation tokens;
  exhausted searches no longer append invented `part N` queries.
- Movies uses the same MovieBox service through its public website. Native
  cards come from server-rendered Nuxt catalogue/search payloads, and related
  titles from the public `subject/detail-rec` endpoint. Large title IDs remain
  strings. Search exposes the first public result page only, rather than
  inventing pagination. Playback is through MovieBox's own in-app web player;
  membership rules and availability continue to apply there. No APK account
  credentials or private native API tokens are reused.
- MovieBox changes domains and response formats; the provider isolates parsing
  and presents retry controls when the service cannot be reached.

Public references checked:

- [MovieBox website](https://moviebox.ph/) (redirected to `movieboxhd.net`).
- [Public movie search](https://movieboxhd.net/web/searchResult?keyword=Inception).
- [JioSaavn radio request schema](https://github.com/saavn-labs/sdk/blob/main/src/saavn/operations/web-radio/schema.ops.ts).

## Verification

```powershell
flutter analyze lib/
flutter test
flutter test tool/discovery_live_test.dart
dart run tool/movie_live_check.dart
flutter build apk --release --target-platform android-arm64
```

Live checks validated both music catalogues, searches, song radios, music stream
URL resolution and audio byte reads at the beginning and past 1.5 MB, plus
YouTube video discovery; MovieBox's four categories, title
search and related titles. The public MovieBox detail/Watch Online page was
also checked in a browser. Full movie playback on a physical Android device is
not part of these checks.
