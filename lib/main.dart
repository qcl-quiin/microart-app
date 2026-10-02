import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'shared/widgets/main_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MicroArtApp());
}

class MicroArtApp extends StatelessWidget {
  const MicroArtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MicroArt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainScaffold(),
    );
  }
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(
      color: Colors.transparent,
      child: _RecognitionOverlay(),
    ),
  ));
}

enum _Stage { idle, framing, recording, processing, result, resultExpanded }

class _RecognitionOverlay extends StatefulWidget {
  const _RecognitionOverlay();

  @override
  State<_RecognitionOverlay> createState() => _RecognitionOverlayState();
}

class _RecognitionOverlayState extends State<_RecognitionOverlay> {
  _Stage _stage = _Stage.idle;
  double _frameSize = 180;
  static const double _minFrame = 120;
  static const double _maxFrame = 360;

  int _secondsLeft = 10;
  bool _waitingForRecordingStart = false;
  bool _isReal = true;
  double _confidence = 0;
  String _description = '';
  int? _historyId;

  int _processingCaptionIndex = 0;
  static const List<String> _processingCaptions = ['Đang tải lên...', 'Đang xử lý...', 'Đang nhận kết quả...'];

  Timer? _countdownTimer;
  Timer? _captionTimer;
  Timer? _resultPollTimer;
  Timer? _recordingStartPollTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _captionTimer?.cancel();
    _resultPollTimer?.cancel();
    _recordingStartPollTimer?.cancel();
    super.dispose();
  }

  // resizeOverlay không tự giữ nguyên vị trí — tự lấy vị trí hiện tại,
  // resize xong thì set lại đúng vị trí đó để tránh giật/nhảy.
  Future<void> _resizeKeepingPosition(int width, int height) async {
    final pos = await FlutterOverlayWindow.getOverlayPosition();
    await FlutterOverlayWindow.resizeOverlay(width, height, true);
    await FlutterOverlayWindow.moveOverlay(OverlayPosition(pos.x, pos.y));
  }

  // QUAN TRỌNG: resize cửa sổ XONG rồi mới setState đổi giao diện — nếu
  // đổi giao diện trước, nội dung mới (cần nhiều chỗ hơn) bị nhồi vào
  // cửa sổ cũ còn nhỏ trong 1 khung hình, Flutter báo lỗi tràn khung
  // (ô vằn vàng-đen) chớp nhoáng trước khi resize kịp hoàn tất.
  Future<void> _openFraming() async {
    await _resizeKeepingPosition(_frameSize.toInt(), _frameSize.toInt());
    if (!mounted) return;
    setState(() => _stage = _Stage.framing);
  }

  Future<void> _changeFrameSize(double delta) async {
    final next = (_frameSize + delta).clamp(_minFrame, _maxFrame);
    if (next == _frameSize) return;
    setState(() => _frameSize = next);
    await _resizeKeepingPosition(_frameSize.toInt(), _frameSize.toInt());
  }

  Future<void> _confirmFrame() async {
    final pos = await FlutterOverlayWindow.getOverlayPosition();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recording_started'); // dọn rác cũ trước khi chờ tín hiệu mới
    await prefs.setString('pending_rect', jsonEncode({
      'left': pos.x,
      'top': pos.y,
      'width': _frameSize,
      'height': _frameSize,
    }));

    await _resizeKeepingPosition(64, 64);
    if (!mounted) return;
    setState(() {
      _stage = _Stage.recording;
      _waitingForRecordingStart = true;
      _secondsLeft = 10;
    });

    _waitForRecordingStart();
  }

  // Chờ máy chính báo đã gọi xong startRecordScreen (thành công hay lỗi
  // đều tính), mới bắt đầu đếm ngược 10s thật. Có timeout 5s dự phòng để
  // overlay không bao giờ đứng hình vĩnh viễn nếu lỡ mất tín hiệu.
  void _waitForRecordingStart() {
    // Chờ tối đa 60s, KHÔNG phải 5s: tín hiệu recording_started chỉ được
    // báo SAU KHI người dùng đọc và bấm "Bắt đầu" trên hộp thoại xin quyền
    // ghi màn hình của hệ thống (Android 14+ hỏi lại MỖI LẦN ghi), nên cần
    // đủ thời gian cho người thật thao tác. 60s chỉ là lưới an toàn.
    final deadline = DateTime.now().add(const Duration(seconds: 60));

    _recordingStartPollTimer?.cancel();
    _recordingStartPollTimer = Timer.periodic(const Duration(milliseconds: 300), (t) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final cancelled = prefs.getBool('recording_cancelled') ?? false;
      if (cancelled) {
        t.cancel();
        await prefs.remove('recording_cancelled');
        print('[MicroArt] overlay: ghi màn hình bị hủy/từ chối, đóng overlay');
        _resetToIdle();
        await FlutterOverlayWindow.closeOverlay();
        return;
      }

      final started = prefs.getBool('recording_started') ?? false;
      if (started) {
        t.cancel();
        await prefs.remove('recording_started');
        print('[MicroArt] overlay: nhận recording_started, bắt đầu đếm ngược');
        if (!mounted) return;
        setState(() => _waitingForRecordingStart = false);
        _startCountdown();
        return;
      }

      if (DateTime.now().isAfter(deadline)) {
        t.cancel();
        print('[MicroArt] overlay: chờ quá 60s không có tín hiệu ghi màn hình, đóng overlay');
        _resetToIdle();
        await FlutterOverlayWindow.closeOverlay();
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (_secondsLeft > 1) {
          _secondsLeft--;
        } else {
          t.cancel();
          _switchToProcessing();
        }
      });
    });
  }

  Future<void> _switchToProcessing() async {
    await _resizeKeepingPosition(220, 64);
    if (!mounted) return;
    setState(() {
      _stage = _Stage.processing;
      _processingCaptionIndex = 0;
    });

    _captionTimer?.cancel();
    _captionTimer = Timer.periodic(const Duration(milliseconds: 1300), (t) {
      if (_processingCaptionIndex < _processingCaptions.length - 1) {
        setState(() => _processingCaptionIndex++);
      } else {
        t.cancel();
      }
    });

    _resultPollTimer?.cancel();
    _resultPollTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('pending_result');
      if (raw == null) return;
      await prefs.remove('pending_result');
      t.cancel();
      _captionTimer?.cancel();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _stage = _Stage.result;
        _isReal = map['isReal'] as bool;
        _confidence = (map['confidence'] as num).toDouble();
        _description = map['description'] as String;
        _historyId = map['historyId'] as int?;
      });
    });
  }

  Future<void> _expandResult() async {
    await _resizeKeepingPosition(280, 200);
    if (!mounted) return;
    setState(() => _stage = _Stage.resultExpanded);
  }

  Future<void> _retry() async {
    await _resizeKeepingPosition(180, 180);
    if (!mounted) return;
    setState(() {
      _stage = _Stage.framing;
      _frameSize = 180;
    });
  }

  // Reset toàn bộ state về idle trước khi đóng — bắt buộc, vì
  // flutter_overlay_window TÁI SỬ DỤNG cùng 1 engine cho các lần
  // showOverlay() sau, không gọi lại overlayMain()/runApp() từ đầu.
  // Nếu không reset ở đây, lần mở overlay kế tiếp sẽ vẫn giữ _stage cũ
  // (ví dụ resultExpanded) nhưng bị nhồi vào khung 64x64 của idle —
  // gây vỡ layout, bấm không ăn (lỗi đã gặp thực tế).
  void _resetToIdle() {
    _countdownTimer?.cancel();
    _captionTimer?.cancel();
    _resultPollTimer?.cancel();
    _recordingStartPollTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.idle;
      _frameSize = 180;
      _waitingForRecordingStart = false;
      _secondsLeft = 10;
      _processingCaptionIndex = 0;
      _historyId = null;
    });
  }

  Future<void> _viewDetails() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_action', 'view_details');
    if (_historyId != null) {
      await prefs.setInt('pending_action_id', _historyId!);
    }
    _resetToIdle();
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> _close() async {
    _resetToIdle();
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (_stage) {
      case _Stage.idle:
        content = GestureDetector(
          onTap: _openFraming,
          child: const Center(
            child: Icon(Icons.face_retouching_natural, color: Colors.white, size: 26),
          ),
        );
        break;
      case _Stage.framing:
        content = _buildFraming();
        break;
      case _Stage.recording:
        content = Center(
          child: _waitingForRecordingStart
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          )
              : Text('$_secondsLeft', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        );
        break;
      case _Stage.processing:
      case _Stage.result:
        content = _buildPill();
        break;
      case _Stage.resultExpanded:
        content = _buildPanel();
        break;
    }

    final isCircle = _stage == _Stage.idle || _stage == _Stage.recording;
    final isFraming = _stage == _Stage.framing;

    return GestureDetector(
      onTap: (_stage == _Stage.result) ? _expandResult : null,
      child: Container(
        decoration: BoxDecoration(
          color: isFraming ? Colors.transparent : const Color(0xFF1A237E),
          border: isFraming ? Border.all(color: const Color(0xFF43A047), width: 2) : null,
          borderRadius: BorderRadius.circular(
            _stage == _Stage.resultExpanded ? 20 : (isCircle ? 32 : 16),
          ),
        ),
        padding: (isFraming || isCircle) ? EdgeInsets.zero : const EdgeInsets.all(12),
        child: content,
      ),
    );
  }

  Widget _buildFraming() {
    return Stack(
      children: [
        Positioned(
          bottom: 4,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roundIconButton(Icons.remove, () => _changeFrameSize(-20)),
              const SizedBox(width: 8),
              _roundIconButton(Icons.check, _confirmFrame, bg: const Color(0xFF43A047)),
              const SizedBox(width: 8),
              _roundIconButton(Icons.add, () => _changeFrameSize(20)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap, {Color bg = const Color(0xFF1A237E)}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildPill() {
    if (_stage == _Stage.processing) {
      return Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _processingCaptions[_processingCaptionIndex],
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    final color = _isReal ? const Color(0xFF2E9E6D) : const Color(0xFFC62828);
    return Row(
      children: [
        Icon(_isReal ? Icons.check_circle : Icons.cancel, color: color, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_isReal ? 'NGƯỜI THẬT' : 'GIẢ MẠO', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              Text('$_confidence%', style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    final color = _isReal ? const Color(0xFF2E9E6D) : const Color(0xFFC62828);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(_isReal ? Icons.check_circle : Icons.cancel, color: color, size: 28),
            const SizedBox(width: 8),
            Text(_isReal ? 'NGƯỜI THẬT' : 'GIẢ MẠO', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
            const Spacer(),
            Text('$_confidence%', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 6),
        Text(_description, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _viewDetails,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF43A047),
              minimumSize: const Size.fromHeight(32),
            ).copyWith(overlayColor: WidgetStateProperty.all(Colors.transparent)),
            child: const Text('Xem chi tiết', style: TextStyle(fontSize: 12, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _retry,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), minimumSize: const Size.fromHeight(28)),
                child: const Text('Nhận diện lại', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextButton(
                onPressed: _close,
                style: TextButton.styleFrom(foregroundColor: Colors.white70, minimumSize: const Size.fromHeight(28)),
                child: const Text('Đóng', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}