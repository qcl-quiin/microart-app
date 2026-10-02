import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moinsen_screen_recording/moinsen_screen_recording.dart';
import '../../core/navigation/tab_navigation_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/history_entry.dart';
import '../../core/models/notification_entry.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  Timer? _pollTimer;

  static const MethodChannel _nativeChannel = MethodChannel('microart/native');

  @override
  void initState() {
    super.initState();
    _resetStaleOverlayState();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (t) => _checkPending());
  }

  Future<void> _resetStaleOverlayState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_rect');
    await prefs.remove('pending_action');
    await prefs.remove('pending_action_id');
    await prefs.remove('pending_result');
    await prefs.remove('recording_started');
    await prefs.remove('recording_cancelled');
    try {
      final active = await FlutterOverlayWindow.isActive();
      if (active) await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final rectRaw = prefs.getString('pending_rect');
    if (rectRaw != null) {
      await prefs.remove('pending_rect');
      print('[MicroArt] app chính đọc được pending_rect: $rectRaw');
      await _runRecognitionFlow();
      return;
    }

    final action = prefs.getString('pending_action');
    if (action != null) {
      await prefs.remove('pending_action');
      print('[MicroArt] app chính đọc được pending_action: $action');
      if (action == 'view_details') {
        final historyId = prefs.getInt('pending_action_id');
        await prefs.remove('pending_action_id');
        print('[MicroArt] xử lý view_details: đưa app lên trước, mở chi tiết id=$historyId');
        try {
          await _nativeChannel.invokeMethod('bringToFront');
        } catch (e) {
          print('[MicroArt] LỖI (bỏ qua) khi bringToFront: $e');
        }
        if (historyId != null) {
          TabNavigationController.pendingHistoryDetailId.value = historyId;
        }
        TabNavigationController.requestedTabIndex.value = 1; // Lịch sử
      }
    }
  }

  Future<void> _moveAppToBackground() async {
    try {
      await _nativeChannel.invokeMethod('moveTaskToBack');
    } catch (e) {
      print('[MicroArt] LỖI (bỏ qua) khi minimize app: $e');
    }
  }

  Future<void> _runRecognitionFlow() async {
    print('[MicroArt] _runRecognitionFlow() bắt đầu');

    final videoName = 'microart_${DateTime.now().millisecondsSinceEpoch}';
    bool started = false;

    try {
      started = await MoinsenScreenRecording.startRecordScreen(
        videoName,
        titleNotification: 'MicroArt đang ghi hình',
        messageNotification: 'Đang ghi lại phiên nhận diện...',
      );
      print('[MicroArt] startRecordScreen trả về: $started');
      if (started) {
        await _moveAppToBackground();
      }
    } catch (e) {
      print('[MicroArt] LỖI khi bắt đầu ghi màn hình: $e');
      started = false;
    }

    final prefs = await SharedPreferences.getInstance();

    if (!started) {
      print('[MicroArt] ghi màn hình không được cấp phép/thất bại, hủy phiên nhận diện');
      await prefs.setBool('recording_cancelled', true);
      return;
    }

    await prefs.setBool('recording_started', true);
    print('[MicroArt] đã báo recording_started cho overlay');

    await Future.delayed(const Duration(seconds: 10));

    try {
      final videoPath = await MoinsenScreenRecording.stopRecordScreen;
      print('[MicroArt] đã dừng ghi màn hình, file: $videoPath');
    } catch (e) {
      print('[MicroArt] LỖI khi dừng ghi màn hình: $e');
    }

    // TODO (Bước 4): upload video lên modal.com, nhận kết quả thật,
    // xóa file local ngay sau khi gửi thành công. Hiện tại vẫn giữ file
    // lại (chưa xóa) và dùng kết quả mock bên dưới.
    await Future.delayed(const Duration(milliseconds: 1500));

    final isReal = DateTime.now().second % 2 == 0;
    final confidence = isReal ? 92.5 : 85.0;
    final description = isReal
        ? 'Phát hiện vi chuyển động tự nhiên. Xác suất người thật cao.'
        : 'Không phát hiện vi chuyển động. Có dấu hiệu giả mạo.';

    final historyId = await DatabaseHelper.instance.insertHistory(HistoryEntry(
      result: isReal ? 'REAL' : 'FAKE',
      confidence: confidence,
      description: description,
      timestamp: DateTime.now(),
    ));
    await DatabaseHelper.instance.insertNotification(NotificationEntry(
      title: isReal ? 'Nhận diện hoàn tất' : 'Cảnh báo',
      body: '${isReal ? "Kết quả: NGƯỜI THẬT" : "Phát hiện dấu hiệu giả mạo"} — $confidence%',
      timestamp: DateTime.now(),
    ));

    await prefs.setString('pending_result', jsonEncode({
      'isReal': isReal,
      'confidence': confidence,
      'description': description,
      'historyId': historyId,
    }));
    print('[MicroArt] đã ghi pending_result vào SharedPreferences (historyId=$historyId)');
  }

  Future<void> _startRecognition() async {
    try {
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        final result = await FlutterOverlayWindow.requestPermission();
        if (result != true) return;
      }
      final active = await FlutterOverlayWindow.isActive();
      print('[MicroArt] _startRecognition: isActive = $active');
      if (active) {
        print('[MicroArt] _startRecognition: đang đóng overlay cũ...');
        await FlutterOverlayWindow.closeOverlay();
        print('[MicroArt] _startRecognition: đã đóng xong, đợi 300ms');
        await Future.delayed(const Duration(milliseconds: 300));
      }
      print('[MicroArt] _startRecognition: gọi showOverlay()');
      await FlutterOverlayWindow.showOverlay(
        height: 64,
        width: 64,
        alignment: OverlayAlignment.centerLeft,
        enableDrag: true,
      );
      print('[MicroArt] _startRecognition: showOverlay() xong');
    } catch (e) {
      print('[MicroArt] _startRecognition LỖI: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận diện'),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}, tooltip: 'Hướng dẫn'),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text('Sẵn sàng',
                            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.green, fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Bắt đầu nhận diện', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text('Mở video call, sau đó nhấn nút bên dưới để bắt đầu quét khuôn mặt.', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text('Các bước thực hiện', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              const _StepItem(number: 1, text: 'Mở ứng dụng video call (Zalo, Zoom, Meet...)'),
              const _StepItem(number: 2, text: 'Quay lại MicroArt và nhấn "Bắt đầu nhận diện"'),
              const _StepItem(number: 3, text: 'Bấm vào bong bóng, kéo/chỉnh khung tới khuôn mặt cần xác thực'),
              const _StepItem(number: 4, text: 'Chờ ~10 giây để nhận kết quả'),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startRecognition,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Bắt đầu nhận diện'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final int number;
  final String text;

  const _StepItem({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(8)),
            child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: theme.textTheme.bodyLarge))),
        ],
      ),
    );
  }
}