# moinsen_screen_recording

A **Gradle-9-clean fork** of
[`flutter_screen_recording`](https://pub.dev/packages/flutter_screen_recording)
(isvisoft) `2.0.25`. Native screen recording on Android / iOS / Web.

## Why this fork exists

Upstream `flutter_screen_recording 2.0.25` is unmaintained and its Android
`build.gradle` declares two **dead / unreachable repositories** that a
Gradle 9 app build fails on (Gradle 8 merely tries and skips them):

1. **`jcenter()`** — shut down in 2021.
2. **`https://artifact.bytedance.com/repository/Volcengine/`** — a
   third-party repo, unreachable in most networks.

This fork removes exactly those two. Everything that already works is
kept as-is — including the native recorder
`com.github.HBiSoft:HBRecorder` from **jitpack**, a live repo the plugin
injects via `rootProject.allprojects`, so consuming apps still need
**no repository config of their own**.

> An earlier iteration tried to vendor HBRecorder as a local `.aar`, but
> AGP forbids `implementation files('*.aar')` in a library module
> ("Direct local .aar file dependencies are not supported when building
> an AAR"). The jitpack dependency is the correct mechanism.

The Dart / iOS code is unchanged from upstream; only the two dead repos
are gone and the entry-point class is renamed `MoinsenScreenRecording`.

## Usage

```dart
import 'package:moinsen_screen_recording/moinsen_screen_recording.dart';

final started = await MoinsenScreenRecording.startRecordScreen(
  'my_recording',
  titleNotification: 'Recording',
  messageNotification: 'Screen recording in progress…',
);
// …
final filePath = await MoinsenScreenRecording.stopRecordScreen;
```

API is identical to upstream `FlutterScreenRecording` (class renamed).

## Credit & license

Forked from isvisoft/flutter_screen_recording, MIT-licensed — original
copyright preserved in `LICENSE`. Maintained by moinsen-dev for the
[TesterPayKit](https://testerpaykit.com) SDK.
