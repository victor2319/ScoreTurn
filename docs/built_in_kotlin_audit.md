# Built-in Kotlin dependency audit (2026-10-25)

Checked pub.dev changelogs and the actual published package archives, rather
than relying on repository main branches. This is a source audit, not a
successful Flutter dependency resolution or Android build.

| Package | Audited version | Finding |
| --- | --- | --- |
| android_file_picker | 2.1.1 | Conditionally applies KGP only when built-in Kotlin is disabled or AGP is below 9. pub.dev marks this version Built-in Kotlin-ready. |
| record_android | 2.1.2 | Android library plugin plus Kotlin compilerOptions; does not apply the Kotlin Android plugin. Keep record at ^7.1.2. |
| pdfx | 2.11.0 | Changelog adds built-in Kotlin support in 2.10.0. Published script checks android.builtInKotlin before applying KGP. |
| wakelock_plus | 1.8.2 | Changelog records migration in 1.7.0. Published script applies KGP only for AGP below 9. |
| package_info_plus | 10.2.2 | Adds built-in support in 10.2.0 and corrects explicit opt-out handling in 10.2.2. Indirect dependency of wakelock_plus. |
| path_provider_android | 2.3.1 | Uses JNI; published archive has no Android Gradle build script. |
| jni_flutter | 1.0.4+1 | Android Java library script does not apply KGP. Indirect dependency of path_provider_android. |

The audited versions below are reference findings, not dependency changes.
The manifest retains file_picker ^13.1.0 and the original direct dependencies;
no additional transitive constraints or dependency_overrides were applied.

No new upstream issue was filed: compatible published implementations exist.
Existing file_picker reports include #2093 and #2200 in
https://github.com/vicajilau/flutter_file_picker/issues .

The repository has no pubspec.lock, and the user's Windows lockfile was not
available. Actual installed versions must be checked after dependency refresh.
The previously supplied log fails while closing Kotlin incremental caches;
that does not establish missing built-in Kotlin support.

## Windows verification

After pulling these changes, run from the project root:

```powershell
flutter pub upgrade
flutter pub deps --style=compact
flutter analyze
flutter test
flutter clean
flutter pub get
flutter build apk --debug
```

Stop at a failed command and retain its output. Keep the local
`kotlin.incremental=false` workaround while checking the cache failure.
This setting is independent of `android.builtInKotlin`.

Do not simply toggle android.builtInKotlin=true to hide a warning. Enabling
that mode requires AGP 9+, Flutter 3.47+, and checking the generated app's
Kotlin plugin application and compiler configuration. The generated android/
project is not currently in this repository and was not migrated by this audit.

## Primary sources

- https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
- https://pub.dev/packages/android_file_picker/changelog
- https://pub.dev/packages/android_file_picker/score
- https://pub.dev/packages/record_android/changelog
- https://pub.dev/packages/pdfx/changelog
- https://pub.dev/packages/wakelock_plus/changelog
- https://pub.dev/packages/package_info_plus/changelog
- https://pub.dev/packages/path_provider_android/changelog
- https://pub.dev/packages/jni_flutter/changelog

Published build scripts were read from each version's archive URL returned by
https://pub.dev/api/packages/PACKAGE/versions/VERSION .
