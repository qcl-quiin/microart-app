// moinsen_screen_recording — a Gradle-9-clean fork of
// isvisoft/flutter_screen_recording 2.0.25.
//
// The Dart facade is unchanged from upstream (thin wrapper over
// flutter_screen_recording_platform_interface + flutter_foreground_task);
// the only reason this fork exists is the Android build.gradle, which
// upstream ships with a `rootProject.allprojects { repositories }`
// mutation + an imperative `buildscript { classpath AGP }` + jcenter()
// — all rejected by Gradle 9. Here those are gone and the native
// recorder (HBRecorder) is vendored as android/libs/HBRecorder-2.0.5.aar
// so no per-app jitpack repo is needed. Class renamed to
// MoinsenScreenRecording; API identical.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_screen_recording_platform_interface/flutter_screen_recording_platform_interface.dart';

class MoinsenScreenRecording {
  static Future<bool> startRecordScreen(
    String name, {
    String? titleNotification,
    String? messageNotification,
  }) async {
    try {
      titleNotification ??= '';
      messageNotification ??= '';

      if (!kIsWeb) {
        _maybeStartFGS(titleNotification, messageNotification);
      }
      final start =
          await FlutterScreenRecordingPlatform.instance.startRecordScreen(
        name,
        notificationTitle: titleNotification,
        notificationMessage: messageNotification,
      );
      return start;
    } catch (err) {
      debugPrint('startRecordScreen err: $err');
    }
    return false;
  }

  static Future<bool> startRecordScreenAndAudio(
    String name, {
    String? titleNotification,
    String? messageNotification,
  }) async {
    try {
      titleNotification ??= '';
      messageNotification ??= '';
      if (!kIsWeb) {
        _maybeStartFGS(titleNotification, messageNotification);
      }
      final start = await FlutterScreenRecordingPlatform.instance
          .startRecordScreenAndAudio(
        name,
        notificationTitle: titleNotification,
        notificationMessage: messageNotification,
      );
      return start;
    } catch (err) {
      debugPrint('startRecordScreenAndAudio err: $err');
    }
    return false;
  }

  static Future<String> get stopRecordScreen async {
    try {
      final path =
          await FlutterScreenRecordingPlatform.instance.stopRecordScreen;
      if (!kIsWeb && Platform.isAndroid) {
        FlutterForegroundTask.stopService();
      }
      return path;
    } catch (err) {
      debugPrint('stopRecordScreen err: $err');
    }
    return '';
  }

  static void _maybeStartFGS(
    String titleNotification,
    String messageNotification,
  ) {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'notification_channel_id',
            channelName: titleNotification,
            channelDescription: messageNotification,
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: true,
            playSound: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.repeat(5000),
            autoRunOnBoot: true,
            autoRunOnMyPackageReplaced: true,
            allowWakeLock: true,
            allowWifiLock: true,
          ),
        );
      }
    } catch (err) {
      debugPrint('_maybeStartFGS err: $err');
    }
  }
}
