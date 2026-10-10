import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
      title: 'MicroAct',
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

// Luồng (app đã ghi màn hình từ lúc người dùng cấp quyền):
//   framing  : khung xanh lá — người dùng phóng to cuộc gọi, kéo khung che MẶT CỦA CHÍNH MÌNH (ô tự xem),
//              rồi bấm ✓. Server BỎ QUA mọi khuôn mặt nằm trong khung này (vì một số app như Messenger có thể
//              hoán đổi ô lớn/nhỏ, nên không thể chọn mặt theo kích thước). ✓ cũng là mốc "Xác nhận".
//   recording: bong bóng đếm ngược 10 giây nằm NGAY TRONG vùng khung (vùng đã bị loại nên không che đối tượng)
//   processing -> result -> resultExpanded, hoặc error nếu có lỗi
enum _Stage { framing, recording, processing, result, resultExpanded, error }

class _RecognitionOverlay extends StatefulWidget {
  const _RecognitionOverlay();

  @override
  State<_RecognitionOverlay> createState() => _RecognitionOverlayState();
}

class _RecognitionOverlayState extends State<_RecognitionOverlay> {
  _Stage _stage = _Stage.framing;
  bool _confirming = false;

  double _frameSize = 180;
  static const double _minFrame = 160; // phải >= chiều rộng bong bóng (150) để bong bóng nằm gọn trong vùng khung
  static const double _maxFrame = 360;
  static const int _pillWidth = 150;
  static const int _pillHeight = 64;

  double _screenW = 0;
  double _screenH = 0;

  int _secondsLeft = 10;
  bool _isReal = true;
  double _confidence = 0;
  String _description = '';
  int? _historyId;

  int _processingCaptionIndex = 0;
  static const List<String> _processingCaptions = ['Đang tải lên...', 'Đang xử lý...', 'Đang phân tích...'];

  Timer? _countdownTimer;
  Timer? _captionTimer;
  Timer? _resultPollTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _captionTimer?.cancel();
    _resultPollTimer?.cancel();
    super.dispose();
  }

  // Kích thước màn hình (dp) do app chính ghi vào SharedPreferences — overlay không tự biết được vì
  // "màn hình" của nó chỉ là cửa sổ nhỏ của chính nó.
  Future<void> _loadScreenSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    _screenW = prefs.getDouble('screen_w_dp') ?? 0;
    _screenH = prefs.getDouble('screen_h_dp') ?? 0;
  }

  // Kích thước/vị trí overlay tính bằng dp (đã kiểm tra trong mã nguồn plugin: dpToPx/pxToDp), gốc toạ độ là
  // góc trên-trái màn hình khi dùng OverlayAlignment.topLeft. resizeOverlay không tự giữ nguyên vị trí nên tự
  // lấy vị trí hiện tại rồi đặt lại; keepOnScreen kéo cửa sổ vào trong màn hình nếu resize làm nó tràn ra ngoài.
  Future<void> _resizeKeepingPosition(int width, int height, {bool keepOnScreen = false}) async {
    final pos = await FlutterOverlayWindow.getOverlayPosition();
    await FlutterOverlayWindow.resizeOverlay(width, height, true);
    double x = pos.x;
    double y = pos.y;
    if (keepOnScreen && _screenW > 0 && _screenH > 0) {
      x = math.min(math.max(x, 0.0), math.max(0.0, _screenW - width));
      y = math.min(math.max(y, 0.0), math.max(0.0, _screenH - height));
    }
    await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
  }

  Future<void> _changeFrameSize(double delta) async {
    final next = (_frameSize + delta).clamp(_minFrame, _maxFrame).toDouble();
    if (next == _frameSize) return;
    await _loadScreenSize();
    setState(() => _frameSize = next);
    await _resizeKeepingPosition(next.toInt(), next.toInt(), keepOnScreen: true);
  }

  // Bấm ✓: ghi lại VÙNG MẶT CỦA BẠN (vị trí + kích thước khung, đơn vị dp, kèm mật độ điểm ảnh để server đổi
  // sang pixel) và MỐC THỜI GIAN xác nhận (app cắt bỏ phần video trước mốc này), rồi thu khung lại thành bong
  // bóng đếm ngược — bong bóng giữ nguyên góc trên-trái của khung nên nằm gọn trong vùng khung.
  Future<void> _confirm() async {
    if (_confirming) return;
    _confirming = true;
    final pos = await FlutterOverlayWindow.getOverlayPosition();
    final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('self_zone', jsonEncode({
      'left': pos.x,
      'top': pos.y,
      'width': _frameSize,
      'height': _frameSize,
      'density': dpr,
    }));
    await prefs.setInt('confirm_ms', DateTime.now().millisecondsSinceEpoch);
    await _resizeKeepingPosition(_pillWidth, _pillHeight);
    if (!mounted) return;
    setState(() {
      _stage = _Stage.recording;
      _secondsLeft = 10;
    });
    _startCountdown();
  }

  Future<void> _cancel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cancel_session', true);
    _resetToFraming();
    await FlutterOverlayWindow.closeOverlay();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        t.cancel();
        _switchToProcessing();
      }
    });
  }

  // Bong bóng giữ nguyên kích thước (150x64) qua các bước đếm ngược/xử lý/kết quả để luôn nằm trong vùng khung
  // (video vẫn đang được ghi thêm khoảng 1.5 giây sau khi hết đếm ngược).
  Future<void> _switchToProcessing() async {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.processing;
      _processingCaptionIndex = 0;
    });

    _captionTimer?.cancel();
    _captionTimer = Timer.periodic(const Duration(milliseconds: 1300), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
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

      final errorText = map['error'];
      if (errorText is String) {
        await _loadScreenSize();
        await _resizeKeepingPosition(280, 150, keepOnScreen: true);
        if (!mounted) return;
        setState(() {
          _stage = _Stage.error;
          _description = errorText;
        });
        return;
      }

      setState(() {
        _stage = _Stage.result;
        _isReal = map['isReal'] as bool;
        _confidence = (map['confidence'] as num).toDouble();
        _description = map['description'] as String;
        _historyId = map['historyId'] as int?;
      });
    });
  }

  // Luôn resize cửa sổ XONG rồi mới setState đổi giao diện — nếu đổi giao diện trước, nội dung
  // mới (cần nhiều chỗ hơn) bị nhồi vào cửa sổ cũ còn nhỏ, Flutter báo tràn khung chớp nhoáng.
  Future<void> _expandResult() async {
    await _loadScreenSize();
    await _resizeKeepingPosition(280, 200, keepOnScreen: true);
    if (!mounted) return;
    setState(() => _stage = _Stage.resultExpanded);
  }

  // "Nhận diện lại": báo app chính bắt đầu phiên mới (xin quyền ghi màn hình lại), rồi đóng overlay.
  Future<void> _retry() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_action', 'retry');
    _resetToFraming();
    await FlutterOverlayWindow.closeOverlay();
  }

  // Reset toàn bộ state về framing trước khi đóng — bắt buộc, vì flutter_overlay_window
  // TÁI SỬ DỤNG cùng 1 engine cho các lần showOverlay() sau, không gọi lại overlayMain()/runApp().
  // Nếu không reset ở đây, lần mở overlay kế tiếp vẫn giữ _stage cũ (ví dụ resultExpanded)
  // nhưng bị nhồi vào cửa sổ khung — vỡ layout, bấm không ăn.
  void _resetToFraming() {
    _countdownTimer?.cancel();
    _captionTimer?.cancel();
    _resultPollTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.framing;
      _confirming = false;
      _frameSize = 180;
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
    _resetToFraming();
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> _close() async {
    _resetToFraming();
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (_stage) {
      case _Stage.framing:
        content = _buildFraming();
        break;
      case _Stage.recording:
        content = _buildRecording();
        break;
      case _Stage.processing:
      case _Stage.result:
        content = _buildPill();
        break;
      case _Stage.resultExpanded:
        content = _buildPanel();
        break;
      case _Stage.error:
        content = _buildError();
        break;
    }

    final isFraming = _stage == _Stage.framing;
    final isBox = _stage == _Stage.resultExpanded || _stage == _Stage.error;

    return GestureDetector(
      onTap: (_stage == _Stage.result) ? _expandResult : null,
      child: Container(
        decoration: BoxDecoration(
          color: isFraming ? Colors.transparent : const Color(0xFF1A237E),
          border: isFraming ? Border.all(color: const Color(0xFF43A047), width: 2) : null,
          borderRadius: BorderRadius.circular(isBox ? 20 : 16),
        ),
        padding: isFraming ? EdgeInsets.zero : const EdgeInsets.all(12),
        child: content,
      ),
    );
  }

  Widget _buildFraming() {
    return Stack(
      children: [
        Positioned(
          top: 4,
          left: 4,
          right: 32,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xE6000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Kéo khung vào đúng MẶT BẠN rồi bấm ✓',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, height: 1.25),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: _roundIconButton(Icons.close, _cancel, bg: const Color(0xFFC62828), size: 24),
        ),
        Positioned(
          bottom: 4,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roundIconButton(Icons.remove, () => _changeFrameSize(-20)),
              const SizedBox(width: 8),
              _roundIconButton(Icons.check, _confirm, bg: const Color(0xFF43A047)),
              const SizedBox(width: 8),
              _roundIconButton(Icons.add, () => _changeFrameSize(20)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap, {Color bg = const Color(0xFF1A237E), double size = 32}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: size * 0.56),
      ),
    );
  }

  Widget _buildRecording() {
    return Row(
      children: [
        Text('$_secondsLeft', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Đừng chạm\nmàn hình',
            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    const warn = Color(0xFFFFB300);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.error_outline, color: warn, size: 22),
            SizedBox(width: 8),
            Text('Chưa nhận diện được', style: TextStyle(color: warn, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        Text(_description, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 4, overflow: TextOverflow.ellipsis),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _retry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  minimumSize: const Size.fromHeight(30),
                ),
                child: const Text('Thử lại', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextButton(
                onPressed: _close,
                style: TextButton.styleFrom(foregroundColor: Colors.white70, minimumSize: const Size.fromHeight(30)),
                child: const Text('Đóng', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
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
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _processingCaptions[_processingCaptionIndex],
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
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
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_isReal ? 'NGƯỜI THẬT' : 'GIẢ MẠO', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              Text('${_confidence.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70, fontSize: 10)),
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
            Text('${_confidence.toStringAsFixed(1)}%', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
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
