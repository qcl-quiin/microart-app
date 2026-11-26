import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moinsen_screen_recording/moinsen_screen_recording.dart';
import 'package:video_compress/video_compress.dart';
import '../../core/navigation/tab_navigation_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/history_entry.dart';
import '../../core/models/notification_entry.dart';
import 'firebase_endpoint.dart';

// Log chỉ in khi chạy bản debug (flutter run), hoặc khi build kèm --dart-define=MICROART_LOG=true.
// Bản release bình thường KHÔNG in gì ra logcat (tránh lộ tên tệp, đường dẫn).
const bool _kVerboseLog = bool.fromEnvironment('MICROART_LOG');

void _log(String message) {
  if (kDebugMode || _kVerboseLog) debugPrint(message);
}

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> with WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _busy = false;
  // Quyền "hiển thị trên ứng dụng khác" (overlay). null = đang kiểm tra; false = chưa cấp -> hiện nút Cấp quyền, khoá nút Nhận diện.
  bool? _overlayGranted;

  static const MethodChannel _nativeChannel = MethodChannel('microart/native');

  static const _firebaseDatabase = String.fromEnvironment(
    'MICROACT_FIREBASE_DB',
    defaultValue: 'https://sever-342e8-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
  static const _demoCode = String.fromEnvironment('MICROACT_DEMO_CODE');
  Uri _serverUri = Uri.parse('https://danghoanganhquan6--microart-tang1-tang1service-check-liveness.modal.run');

  // Luồng ghi: app ghi màn hình TỪ LÚC CẤP QUYỀN (plugin hỏi quyền và ghi cùng một lúc), nhưng chỉ
  // phân tích từ lúc người dùng bấm ✓ trên khung. Server cắt bỏ phần đầu theo trim_start_sec.
  static const double _guardSec = 0.8; // bỏ 0.8s đầu sau khi bấm ✓ (thao tác bấm, khung thu lại thành bong bóng)
  static const double _captureSec = 10.0; // đoạn phân tích
  static const double _tailBufferSec = 0.7; // ghi thêm một chút cho an toàn khi sai lệch đồng hồ
  static const int _skipCompressBytes = 10 * 1024 * 1024; // file gốc nhỏ hơn mức này thì KHÔNG nén (nén tốn 20-30s, tiết kiệm ít)
  static const double _minAnalysisSec = 8.0; // video nén có ít hơn ngần này giây phân tích thì không dùng (gửi file gốc)
  static const int _confirmTimeoutSec = 90; // quá lâu không bấm ✓ thì huỷ (file ghi sẽ phình to)

  // Kích thước khung chọn mặt ban đầu (dp) — phải khớp _frameSize mặc định bên overlay (main.dart).
  static const int _frameStartSize = 180;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshOverlayPermission();
    _resetStaleOverlayState();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (t) => _checkPending());
  }

  Future<void> _resetStaleOverlayState() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      'pending_rect',
      'pending_action',
      'pending_action_id',
      'pending_result',
      'recording_started',
      'recording_cancelled',
      'confirm_ms',
      'cancel_session',
      'self_zone',
    ]) {
      await prefs.remove(key);
    }
    try {
      final active = await FlutterOverlayWindow.isActive();
      if (active) await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  // Quay lại app (VD sau khi cấp quyền ở màn hình cài đặt) thì kiểm tra lại quyền ngay.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshOverlayPermission();
  }

  Future<void> _refreshOverlayPermission() async {
    bool granted = false;
    try {
      granted = await FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      _log('[MicroArt] LỖI khi kiểm tra quyền overlay: $e');
    }
    if (!mounted || _overlayGranted == granted) return;
    setState(() => _overlayGranted = granted);
  }

  // Mở màn hình cấp quyền. KHÔNG chờ kết quả (plugin không trả về khi người dùng rời sang cài đặt);
  // khi quay lại app, didChangeAppLifecycleState sẽ kiểm tra lại.
  void _requestOverlayPermission() {
    unawaited(FlutterOverlayWindow.requestPermission());
  }

  // Chỉ còn xử lý hành động do overlay gửi sang (xem chi tiết / nhận diện lại).
  Future<void> _checkPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final action = prefs.getString('pending_action');
    if (action == null) return;
    await prefs.remove('pending_action');
    _log('[MicroArt] app chính đọc được pending_action: $action');

    if (action == 'view_details') {
      final historyId = prefs.getInt('pending_action_id');
      await prefs.remove('pending_action_id');
      _log('[MicroArt] xử lý view_details: đưa app lên trước, mở chi tiết id=$historyId');
      try {
        await _nativeChannel.invokeMethod('bringToFront');
      } catch (e) {
        _log('[MicroArt] LỖI (bỏ qua) khi bringToFront: $e');
      }
      if (historyId != null) {
        TabNavigationController.pendingHistoryDetailId.value = historyId;
      }
      TabNavigationController.requestedTabIndex.value = 1; // Lịch sử
    } else if (action == 'retry') {
      unawaited(_startRecognition());
    }
  }

  Future<void> _moveAppToBackground() async {
    try {
      await _nativeChannel.invokeMethod('moveTaskToBack');
    } catch (e) {
      _log('[MicroArt] LỖI (bỏ qua) khi minimize app: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Hộp lưu ý hiện MỘT LẦN trước khi bắt đầu (chỉ khi người dùng tự bấm nút, không hiện lại ở "Thử lại").
  Future<bool> _askWarning() async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Lưu ý khi nhận diện'),
        content: const Text(
          '• Sau khi bấm ✓, KHÔNG chạm vào màn hình trong khoảng 10 giây. Một số app (như Messenger) '
          'có thể đổi vị trí hai khuôn mặt khi bạn chạm.\n\n'
          '• Khung xanh phải che đúng MẶT CỦA BẠN (ô nhỏ của bạn trong cuộc gọi). Hệ thống sẽ không '
          'phân tích vùng đó.\n\n'
          '• Bên kia chỉ nên có 1 người.\n\n'
          '• Đoạn video 10 giây được gửi lên máy chủ để phân tích rồi xoá. Hãy xin phép người bên kia '
          'trước khi kiểm tra.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Đã hiểu, tiếp tục')),
        ],
      ),
    );
    return ok == true;
  }

  // Gọi 1 request rỗng để máy chủ khởi động trước (khởi động lạnh mất ~13s) — chạy ngầm trong lúc
  // người dùng cấp quyền và phóng to cuộc gọi, nên khi video được gửi lên thì máy chủ đã sẵn sàng.
  Future<void> _warmUpServer() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.postUrl(_serverUri);
      req.followRedirects = false;
      if (_firebaseDatabase.isNotEmpty) req.headers.set('X-MicroAct-Code', _demoCode);
      req.headers.contentType = ContentType.json;
      final body = utf8.encode(jsonEncode({'frames_base64': <String>[]}));
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(const Duration(seconds: 60));
      await resp.drain();
      _log('[MicroArt] đã đánh thức máy chủ');
    } catch (e) {
      _log('[MicroArt] đánh thức máy chủ không được (bỏ qua): $e');
    } finally {
      client?.close();
    }
  }

  Future<bool> _prepareLaptopEndpoint() async {
    if (_demoCode.isEmpty) {
      _showSnack('Bản MicroAct này chưa có quyền kết nối. Hãy cài bản mới từ ban tổ chức.');
      return false;
    }
    try {
      _serverUri = await readCloudflareEndpoint(_firebaseDatabase);
      return mounted;
    } catch (e) {
      _log('[MicroArt] Không đọc được địa chỉ máy chủ: $e');
      if (mounted) _showSnack('Chưa lấy được địa chỉ máy chủ. Hãy kiểm tra mạng và thử lại.');
      return false;
    }
  }

  Future<void> _startRecognition({bool showWarning = false}) async {
    _log('[MicroArt] bấm Bắt đầu nhận diện (đang bận=$_busy)');
    if (_busy) {
      // Phiên trước còn dang dở (VD khung bị kẹt ngoài màn hình nên không bấm được ✓/✕): yêu cầu nó huỷ rồi chờ
      // nó dọn xong, thay vì im lặng bỏ qua như trước (người dùng thấy "bấm mà không có gì xảy ra").
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cancel_session', true);
      for (var i = 0; i < 20 && _busy; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (_busy) {
        _showSnack('Phiên nhận diện trước vẫn đang xử lý. Đợi vài giây rồi bấm lại.');
        return;
      }
    }
    _busy = true;
    try {
      if (showWarning && !await _askWarning()) return;

      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        // Không xin quyền ở đây nữa (chờ kết quả sẽ làm kẹt cờ _busy); nút "Cấp quyền" trên màn hình lo việc đó.
        if (mounted) setState(() => _overlayGranted = false);
        _showSnack('Cần cấp quyền hiển thị trên ứng dụng khác trước.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (_firebaseDatabase.isNotEmpty && !await _prepareLaptopEndpoint()) return;

      // Dọn tín hiệu cũ và overlay cũ (nếu còn) trước khi bắt đầu phiên mới.
      for (final key in const ['confirm_ms', 'cancel_session', 'self_zone', 'pending_result', 'pending_action', 'pending_action_id']) {
        await prefs.remove(key);
      }
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Kích thước màn hình (dp): overlay dùng để giữ cửa sổ nằm trong màn hình, và để đặt khung ban đầu.
      double screenW = 0;
      double screenH = 0;
      if (mounted) {
        final size = MediaQuery.of(context).size;
        screenW = size.width;
        screenH = size.height;
        await prefs.setDouble('screen_w_dp', screenW);
        await prefs.setDouble('screen_h_dp', screenH);
      }

      unawaited(_warmUpServer());

      // Bước 1: xin quyền ghi màn hình — plugin hỏi quyền và BẮT ĐẦU GHI ngay khi được cấp.
      final videoName = 'microart_${DateTime.now().millisecondsSinceEpoch}';
      bool started = false;
      try {
        started = await MoinsenScreenRecording.startRecordScreen(
          videoName,
          titleNotification: 'MicroAct đang ghi hình',
          messageNotification: 'Đang ghi lại phiên nhận diện...',
        ).timeout(const Duration(seconds: 120));
      } catch (e) {
        _log('[MicroArt] LỖI khi bắt đầu ghi màn hình: $e');
      }
      _log('[MicroArt] startRecordScreen trả về: $started');
      if (!started) {
        _showSnack('Cần cho phép ghi màn hình để nhận diện.');
        return;
      }
      final recStartMs = DateTime.now().millisecondsSinceEpoch;

      // Bước 2: hiện khung chọn mặt của bạn (góc trên-trái màn hình là gốc toạ độ), đặt ban đầu ở góc trên-phải
      // — chỗ ô tự xem thường nằm — rồi đưa app xuống nền để người dùng thấy cuộc gọi.
      //
      // LƯU Ý (đã đọc mã nguồn plugin): showOverlay nhận kích thước bằng PIXEL, còn resizeOverlay/moveOverlay và
      // vị trí dùng DP. Truyền thẳng 180 vào showOverlay chỉ ra cửa sổ ~68dp (khung bị tràn, nút chồng lên nhau;
      // và là lý do bong bóng 64 trước đây bé trên máy thật). Nên đổi dp -> pixel ở đây, rồi đặt lại bằng
      // resizeOverlay (dp) cho chắc.
      final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      final framePx = (_frameStartSize * dpr).round();
      await FlutterOverlayWindow.showOverlay(
        height: framePx,
        width: framePx,
        alignment: OverlayAlignment.topLeft,
        enableDrag: true,
      );
      await _settleOverlay(screenW, screenH);
      await _moveAppToBackground();

      // Bước 3: chờ ✓ -> ghi đủ thời lượng -> dừng -> gửi server.
      await _runSession(recStartMs);
    } catch (e) {
      _log('[MicroArt] _startRecognition LỖI: $e');
      _showSnack('Lỗi: $e');
    } finally {
      _busy = false;
    }
  }

  // Đặt khung vào vị trí ban đầu (dp, gốc là góc trên-trái màn hình). KHÔNG dùng resizeOverlay ở đây: hàm đó
  // chỉ chạy được bên TRONG overlay, gọi từ app chính sẽ không có ai xử lý. Còn cỡ khung đã đúng nhờ showOverlay
  // nhận pixel. Vị trí mặc định của plugin nằm trên mép màn hình (lỗi của plugin: đổi pixel thành dp hai lần),
  // nên bắt buộc phải tự đặt. Dịch vụ overlay khởi động bất đồng bộ (moveOverlay trả về false nếu chưa sẵn
  // sàng) và có thể tự đặt lại vị trí mặc định ngay sau khi khởi động, nên thử lại và KIỂM TRA vị trí thật.
  Future<void> _settleOverlay(double screenW, double screenH) async {
    final startX = screenW > 0 ? (screenW - _frameStartSize - 8).clamp(0.0, screenW).toDouble() : 120.0;
    final startY = screenH > 0 ? screenH * 0.10 : 120.0;
    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      try {
        final moved = await FlutterOverlayWindow.moveOverlay(OverlayPosition(startX, startY));
        if (moved != true) continue;
        final pos = await FlutterOverlayWindow.getOverlayPosition();
        if ((pos.x - startX).abs() < 2 && (pos.y - startY).abs() < 2) {
          _log('[MicroArt] khung đã vào vị trí ($startX, $startY) dp sau ${i + 1} lần thử');
          return;
        }
      } catch (e) {
        _log('[MicroArt] LỖI (thử lại) khi đặt khung ban đầu: $e');
      }
    }
    _log('[MicroArt] CẢNH BÁO: không đặt được vị trí khung ban đầu sau 12 lần thử');
  }

  Future<void> _runSession(int recStartMs) async {
    final prefs = await SharedPreferences.getInstance();

    int? confirmMs;
    final deadline = DateTime.now().add(const Duration(seconds: _confirmTimeoutSec));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
      await prefs.reload();
      if (prefs.getBool('cancel_session') ?? false) {
        await prefs.remove('cancel_session');
        _log('[MicroArt] người dùng huỷ phiên nhận diện');
        await _abortRecording();
        return;
      }
      confirmMs = prefs.getInt('confirm_ms');
      if (confirmMs != null) break;
    }
    if (confirmMs == null) {
      _log('[MicroArt] quá $_confirmTimeoutSec giây chưa bấm ✓, huỷ phiên');
      await _abortRecording();
      return;
    }
    await prefs.remove('confirm_ms');

    // Vùng mặt CỦA BẠN (dp + mật độ điểm ảnh) do overlay ghi cùng lúc với mốc xác nhận.
    Map<String, dynamic>? zone;
    final zoneRaw = prefs.getString('self_zone');
    if (zoneRaw != null) {
      try {
        zone = jsonDecode(zoneRaw) as Map<String, dynamic>;
      } catch (e) {
        _log('[MicroArt] LỖI (bỏ qua) khi đọc self_zone: $e');
      }
      await prefs.remove('self_zone');
    }

    // Kích thước CẢ MÀN HÌNH (dp), lưu lúc bắt đầu phiên: server cần để đổi vị trí khung sang vị trí trong video — plugin
    // ghi màn hình 1080x2424 thành video 720x1280 (khác tỉ lệ) nên video có viền đen và phải tính lại.
    final double screenW = prefs.getDouble('screen_w_dp') ?? 0;
    final double screenH = prefs.getDouble('screen_h_dp') ?? 0;

    // Mốc cắt: giây (tính từ lúc bắt đầu ghi) mà đoạn phân tích bắt đầu = lúc bấm ✓ + một chút bỏ qua.
    final trimStartSec = (confirmMs - recStartMs) / 1000.0 + _guardSec;
    final stopAtMs = confirmMs + ((_guardSec + _captureSec + _tailBufferSec) * 1000).round();
    final waitMs = stopAtMs - DateTime.now().millisecondsSinceEpoch;
    if (waitMs > 0) {
      await Future.delayed(Duration(milliseconds: waitMs));
    }

    String? videoPath;
    try {
      videoPath = await MoinsenScreenRecording.stopRecordScreen.timeout(const Duration(seconds: 20));
    } catch (e) {
      _log('[MicroArt] LỖI khi dừng ghi màn hình: $e');
    }
    _log('[MicroArt] đã dừng ghi màn hình, file: $videoPath, cắt từ giây ${trimStartSec.toStringAsFixed(2)}');
    if (videoPath != null && videoPath.isNotEmpty) {
      await _waitVideoReady(videoPath);
    }
    if (kDebugMode && zone != null) {
      // Dán thẳng vào lệnh test trên máy tính để chạy lại đúng phiên này với ảnh gỡ lỗi:
      final z = zone;
      _log('[MicroArt] THAM SỐ TEST: --start ${trimStartSec.toStringAsFixed(2)} '
          '--zone-dp ${(z['left'] as num).toStringAsFixed(1)},${(z['top'] as num).toStringAsFixed(1)},'
          '${(z['width'] as num).toStringAsFixed(1)},${(z['height'] as num).toStringAsFixed(1)} '
          '--screen-dp ${screenW.toStringAsFixed(2)},${screenH.toStringAsFixed(2)} --debug');
    }

    Map<String, dynamic> outcome;
    if (videoPath == null || videoPath.isEmpty) {
      outcome = {'error': 'Không lấy được video đã ghi. Hãy thử lại.'};
    } else {
      // Cắt đúng đoạn cần phân tích + nén trước khi gửi (nhẹ hơn nhiều, upload nhanh). Lỗi thì gửi file gốc.
      final prepared = await _prepareUpload(videoPath, trimStartSec);
      outcome = await _analyze(prepared.path, prepared.trimSec, zone, screenW, screenH);
      if (prepared.isTemp) {
        await _deleteQuietly(prepared.path);
        try {
          await VideoCompress.deleteAllCache();
        } catch (_) {}
      }
      // Riêng tư: xoá video ngay sau khi gửi. Chỉ GIỮ LẠI khi chạy bản debug (flutter run) để lấy file
      // test trên máy tính; bản release (dùng khi đi thi) luôn xoá.
      if (kDebugMode) {
        _log('[MicroArt] (debug) GIỮ lại file video để test: $videoPath');
      } else {
        await _deleteQuietly(videoPath);
      }
    }
    await _publishOutcome(prefs, outcome);
  }

  // Một số máy (VD vivo) trả đường dẫn video khi file còn đang được hoàn tất (chưa ghi xong phần đóng file) → server báo
  // "không mở được file video". Chờ tới khi dung lượng file hết thay đổi (tối đa ~8 s), rồi kiểm tra đọc được thời lượng.
  Future<void> _waitVideoReady(String path) async {
    try {
      int last = -1;
      int stable = 0;
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < 8000) {
        int len = 0;
        try {
          final f = File(path);
          if (await f.exists()) len = await f.length();
        } catch (_) {}
        if (len > 0 && len == last) {
          stable++;
          if (stable >= 2) break;
        } else {
          stable = 0;
        }
        last = len;
        await Future.delayed(const Duration(milliseconds: 400));
      }
      for (int i = 0; i < 4; i++) {
        double sec = 0;
        try {
          final info = await VideoCompress.getMediaInfo(path);
          sec = (info.duration ?? 0) / 1000.0;
        } catch (_) {}
        if (sec > 0) {
          _log('[MicroArt] video sẵn sàng: ${sec.toStringAsFixed(1)}s, ${(last / 1048576).toStringAsFixed(2)}MB');
          return;
        }
        await Future.delayed(const Duration(milliseconds: 700));
      }
      _log('[MicroArt] CẢNH BÁO: không đọc được thời lượng video, vẫn gửi thử');
    } catch (e) {
      _log('[MicroArt] LỖI khi chờ video: $e');
    }
  }

  // Cắt từ lúc bấm ✓ (làm tròn xuống giây nguyên, phần lẻ để server cắt nốt), giữ vừa đủ đoạn phân tích, giảm bitrate.
  // LƯU Ý: ở package video_compress (đo thực tế trên máy này), tham số `duration` bị hiểu là số giây CẮT BỎ Ở CUỐI,
  // không phải độ dài đoạn giữ lại. Vì vậy phải tự tính phần đuôi = tổng thời lượng - mốc đầu - đoạn cần giữ.
  // Trả về file để gửi và mốc cắt còn lại cho server. Mọi lỗi/kết quả bất thường đều quay về gửi file gốc.
  Future<_Prepared> _prepareUpload(String originalPath, double trimStartSec) async {
    final fallback = _Prepared(originalPath, trimStartSec, false);
    try {
      final startInt = trimStartSec < 0 ? 0 : trimStartSec.floor();
      final leftover = trimStartSec < 0 ? 0.0 : trimStartSec - startInt;
      final keepSec = leftover + _captureSec + _tailBufferSec + 1.0; // đoạn cần giữ sau mốc cắt (dư 1s cho chắc)
      final origBytes = await File(originalPath).length();
      if (origBytes <= _skipCompressBytes) {
        _log('[MicroArt] bỏ qua bước nén: file gốc ${(origBytes / 1048576).toStringAsFixed(2)}MB <= ${_skipCompressBytes ~/ 1048576}MB; '
            'server tự cắt từ giây ${trimStartSec.toStringAsFixed(2)}');
        return fallback;
      }

      final srcInfo = await VideoCompress.getMediaInfo(originalPath);
      final totalSec = (srcInfo.duration ?? 0) / 1000.0; // duration của MediaInfo tính bằng mili giây
      if (totalSec <= 0 || startInt >= totalSec) {
        _log('[MicroArt] nén video: không đọc được thời lượng (${totalSec}s), gửi file gốc');
        return fallback;
      }
      final tailSec = (totalSec - startInt - keepSec).floor(); // số giây cắt bỏ ở cuối (làm tròn xuống = giữ dư)

      final sw = Stopwatch()..start();
      final info = await VideoCompress.compressVideo(
        originalPath,
        quality: VideoQuality.Res1280x720Quality, // giữ nguyên 720x1280 của video ghi (không co thêm)
        deleteOrigin: false,
        startTime: startInt,
        duration: tailSec > 0 ? tailSec : null,
        includeAudio: false,
        frameRate: 15,
      ).timeout(const Duration(seconds: 60));
      final newPath = info?.path;
      if (newPath == null || newPath.isEmpty) {
        _log('[MicroArt] nén video: không có kết quả, gửi file gốc');
        return fallback;
      }
      final newBytes = await File(newPath).length();
      final outInfo = await VideoCompress.getMediaInfo(newPath);
      final outSec = (outInfo.duration ?? 0) / 1000.0;
      _log('[MicroArt] nén video: ${(origBytes / 1048576).toStringAsFixed(2)}MB -> '
          '${(newBytes / 1048576).toStringAsFixed(2)}MB, mất ${sw.elapsedMilliseconds}ms; '
          'gốc ${totalSec.toStringAsFixed(1)}s, cắt từ giây $startInt, bỏ cuối ${tailSec}s, '
          'còn ${outSec.toStringAsFixed(1)}s, lệch ${leftover.toStringAsFixed(2)}s');
      // An toàn: file ra quá ngắn (không đủ đoạn phân tích) thì không dùng.
      if (newBytes <= 0 || outSec < leftover + _minAnalysisSec) {
        _log('[MicroArt] nén video: kết quả quá ngắn/không hợp lệ, gửi file gốc');
        await _deleteQuietly(newPath);
        return fallback;
      }
      return _Prepared(newPath, leftover, true);
    } catch (e) {
      _log('[MicroArt] LỖI nén video (gửi file gốc): $e');
      return fallback;
    }
  }

  Future<void> _abortRecording() async {
    try {
      final path = await MoinsenScreenRecording.stopRecordScreen.timeout(const Duration(seconds: 20));
      await _deleteQuietly(path);
    } catch (e) {
      _log('[MicroArt] LỖI (bỏ qua) khi dừng ghi lúc huỷ: $e');
    }
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}
  }

  Future<void> _deleteQuietly(dynamic path) async {
    try {
      if (path is String && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}
  }

  // Gửi video (kèm mốc cắt và vùng mặt của bạn) lên máy chủ; trả về {'isReal','confidence','description'}
  // hoặc {'error': '...'}.
  Future<Map<String, dynamic>> _analyze(
      String videoPath, double trimStartSec, Map<String, dynamic>? zone, double screenW, double screenH) async {
    HttpClient? client;
    try {
      final bytes = await File(videoPath).readAsBytes();
      final payload = <String, dynamic>{
        'video_base64': base64Encode(bytes),
        'trim_start_sec': trimStartSec < 0 ? 0.0 : trimStartSec,
      };
      if (zone != null) {
        payload['exclude_zone_dp'] = {
          'left': zone['left'],
          'top': zone['top'],
          'width': zone['width'],
          'height': zone['height'],
        };
        payload['density'] = zone['density'];
        if (screenW > 0 && screenH > 0) {
          payload['screen_dp'] = {'width': screenW, 'height': screenH};
        }
      }
      final body = utf8.encode(jsonEncode(payload));
      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final sw = Stopwatch()..start();
      final req = await client.postUrl(_serverUri);
      req.followRedirects = false;
      if (_firebaseDatabase.isNotEmpty) req.headers.set('X-MicroAct-Code', _demoCode);
      req.headers.contentType = ContentType.json;
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(const Duration(seconds: 200));
      final text = await resp.transform(utf8.decoder).join();
      if (_firebaseDatabase.isNotEmpty && resp.statusCode == HttpStatus.unauthorized) {
        return {'error': 'Bản MicroAct này chưa được cấp quyền. Hãy cài bản mới từ ban tổ chức.'};
      }
      if (resp.statusCode != 200) {
        return {'error': 'Máy chủ trả về lỗi (${resp.statusCode}). Hãy thử lại.'};
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      final timing = data['timing_debug'];
      final srvSec = timing is Map ? timing['total_server_sec'] : null;
      _log('[MicroArt] gửi ${(body.length / 1048576).toStringAsFixed(2)}MB + chờ server: ${sw.elapsedMilliseconds}ms; '
          'server tự báo xử lý: ${srvSec}s');
      final ui = _toUiResult(data);
      final dynamic uiErr = ui['error'];
      if (uiErr is String && uiErr.startsWith('Không đọc được video')) {
        return {'error': 'Video vừa ghi bị lỗi (${(bytes.length / 1048576).toStringAsFixed(2)} MB). Hãy thử lại.'};
      }
      return ui;
    } on TimeoutException {
      return {'error': 'Máy chủ phản hồi quá lâu. Kiểm tra mạng rồi thử lại.'};
    } on SocketException {
      return {'error': 'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.'};
    } catch (e) {
      _log('[MicroArt] LỖI khi phân tích: $e');
      return {'error': 'Có lỗi khi gửi video lên máy chủ.'};
    } finally {
      client?.close();
    }
  }

  // Đổi JSON của máy chủ thành dữ liệu hiển thị. Máy chủ không có "final" (VD không thấy mặt) thì
  // hiện lý do trong "notes".
  Map<String, dynamic> _toUiResult(Map<String, dynamic> data) {
    final dynamic fin = data['final'];
    final dynamic notes = data['notes'];
    final String noteText = notes is String ? notes : '';
    if (fin is! Map || fin['status'] == 'inconclusive') {
      return {'error': noteText.isNotEmpty ? noteText : 'Máy chủ không trả về kết quả.'};
    }
    final bool isReal = fin['is_real'] == true;
    final double percent = ((isReal ? fin['real_pct'] : fin['fake_pct']) as num).toDouble();
    // Máy chủ mới trả câu ngắn riêng cho bong bóng (notes_short). Máy chủ cũ không có thì dùng câu soạn sẵn
    // trong app, để không bao giờ hiện chi tiết kỹ thuật bên trong.
    final dynamic noteShort = data['notes_short'];
    final bool serverHasText = noteShort is String && noteShort.isNotEmpty && noteText.isNotEmpty;
    return {
      'isReal': isReal,
      'confidence': percent,
      'description': serverHasText ? noteText : _detailText(isReal),
      'shortDescription': serverHasText ? noteShort : _shortText(isReal),
    };
  }

  // Câu ngắn hiện ở bong bóng.
  String _shortText(bool isReal) => isReal
      ? 'Chuyển động khuôn mặt tự nhiên, không thấy dấu hiệu bất thường.'
      : 'Phát hiện dấu hiệu bất thường ở khuôn mặt, nghi giả mạo.';

  // Câu chi tiết hơn lưu trong Lịch sử.
  String _detailText(bool isReal) => isReal
      ? 'Hệ thống phân tích chuyển động và đặc điểm khuôn mặt trong đoạn video và không phát hiện dấu hiệu bất thường. '
          'Các biểu hiện nhất quán với một người thật.'
      : 'Hệ thống phát hiện dấu hiệu bất thường ở chuyển động và đặc điểm khuôn mặt. '
          'Khuôn mặt này có khả năng là giả mạo: bị ghép/tạo bằng AI, hoặc là ảnh/video phát lại.';

  // Lưu lịch sử + thông báo (chỉ khi có kết quả thật) rồi báo cho overlay hiển thị.
  Future<void> _publishOutcome(SharedPreferences prefs, Map<String, dynamic> outcome) async {
    final dynamic errorText = outcome['error'];
    if (errorText is String) {
      await prefs.setString('pending_result', jsonEncode({'error': errorText}));
      return;
    }

    final bool isReal = outcome['isReal'] as bool;
    final double confidence = outcome['confidence'] as double;
    final String description = outcome['description'] as String;
    final String shortDescription = (outcome['shortDescription'] as String?) ?? description;

    final historyId = await DatabaseHelper.instance.insertHistory(HistoryEntry(
      result: isReal ? 'REAL' : 'FAKE',
      confidence: confidence,
      description: description,
      timestamp: DateTime.now(),
    ));
    await DatabaseHelper.instance.insertNotification(NotificationEntry(
      title: isReal ? 'Nhận diện hoàn tất' : 'Cảnh báo',
      body: '${isReal ? "Kết quả: NGƯỜI THẬT" : "Phát hiện dấu hiệu giả mạo"} — ${confidence.toStringAsFixed(1)}%',
      timestamp: DateTime.now(),
    ));

    await prefs.setString('pending_result', jsonEncode({
      'isReal': isReal,
      'confidence': confidence,
      'description': description,
      'shortDescription': shortDescription,
      'historyId': historyId,
    }));
    _log('[MicroArt] đã ghi pending_result vào SharedPreferences (historyId=$historyId)');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận diện'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => TabNavigationController.requestedTabIndex.value = 3, // 3 = tab Hướng dẫn
            tooltip: 'Hướng dẫn',
          ),
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
                    Text('Đang trong cuộc gọi video, nhấn nút bên dưới để kiểm tra người bên kia có phải người thật không.',
                        style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text('Các bước thực hiện', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              const _StepItem(number: 1, text: 'Đang trong cuộc gọi video (Zalo, Messenger...), thoát ra màn hình chính để mở MicroAct'),
              const _StepItem(number: 2, text: 'Nhấn "Bắt đầu nhận diện", đọc lưu ý và cho phép ghi màn hình'),
              const _StepItem(number: 3, text: 'Quay lại cuộc gọi, bấm vào cửa sổ cuộc gọi nhỏ để phóng to toàn màn hình'),
              const _StepItem(number: 4, text: 'Kéo khung xanh vào đúng khu vực MẶT CỦA BẠN (camera của bạn trong cuộc gọi), rồi bấm ✓'),
              const _StepItem(number: 5, text: 'KHÔNG chạm vào màn hình, chờ ~10 giây để nhận kết quả'),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _overlayGranted == true ? () => _startRecognition(showWarning: true) : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Bắt đầu nhận diện'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              if (_overlayGranted == false) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _requestOverlayPermission,
                    icon: const Icon(Icons.lock_open_rounded, size: 20),
                    label: const Text('Cấp quyền để ứng dụng hoạt động'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
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

// Video chuẩn bị để gửi: đường dẫn, mốc cắt còn lại cho server (giây), và có phải file tạm cần xoá không.
class _Prepared {
  final String path;
  final double trimSec;
  final bool isTemp;
  const _Prepared(this.path, this.trimSec, this.isTemp);
}
