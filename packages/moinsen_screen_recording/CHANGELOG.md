# Changelog

## 1.0.1

- Fixed iOS package discovery by naming the podspec and CocoaPods spec after
  the published Dart package (`moinsen_screen_recording`).

## 1.0.0

Initial release — a Gradle-9-clean fork of `flutter_screen_recording 2.0.25`.

- Android `build.gradle`: removed the two dead / unreachable repositories
  that break a Gradle 9 app build — `jcenter()` (shut down 2021) and the
  `artifact.bytedance.com` maven repo. On Gradle 8 these were tried-and-
  skipped; Gradle 9 fails harder on unreachable repos.
- Kept the native recorder `com.github.HBiSoft:HBRecorder:2.0.5` on
  jitpack (a live repo, injected via `rootProject.allprojects`), so
  consuming apps still need no repository config of their own. (Vendoring
  it as a local `.aar` is impossible in a library module — AGP: "Direct
  local .aar file dependencies are not supported when building an AAR".)
- Dropped standalone-build leftovers (`android/settings.gradle`,
  `android/gradle.properties` with `enableJetifier`, the gradle wrapper).
- Entry-point class renamed `FlutterScreenRecording` → `MoinsenScreenRecording`;
  method signatures unchanged. Dart facade + iOS implementation otherwise
  identical to upstream.
