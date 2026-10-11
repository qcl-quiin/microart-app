package com.isvisoft.flutter_screen_recording

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.IOException

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding


class FlutterScreenRecordingPlugin : 
    MethodCallHandler, 
    PluginRegistry.ActivityResultListener,
    FlutterPlugin, 
    ActivityAware {

    private var mScreenDensity: Int = 0
    var mMediaRecorder: MediaRecorder? = null
    val mProjectionManager: MediaProjectionManager by lazy {
        ContextCompat.getSystemService(
            pluginBinding!!.applicationContext,
            MediaProjectionManager::class.java
        ) ?: throw Exception("MediaProjectionManager not found")
    }
    var mMediaProjection: MediaProjection? = null
    var mMediaProjectionCallback: MediaProjectionCallback? = null
    var mVirtualDisplay: VirtualDisplay? = null
    private var mDisplayWidth: Int = 1280
    private var mDisplayHeight: Int = 800
    private var videoName: String? = ""
    private var mFileName: String? = ""
    private var mTitle = "Your screen is being recorded"
    private var mMessage = "Your screen is being recorded"
    private var recordAudio: Boolean? = false;
    private val SCREEN_RECORD_REQUEST_CODE = 333

    private var pendingResult: Result? = null

    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var serviceConnection: ServiceConnection? = null
    private var recorderFinalized = true

    private fun completePendingResult(value: Boolean) {
        pendingResult?.success(value)
        pendingResult = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {

        val context = pluginBinding!!.applicationContext
        
        if (requestCode == SCREEN_RECORD_REQUEST_CODE) {
            if (pendingResult == null) {
                Log.w("ScreenRecordingPlugin", "Ignoring activity result with no pending callback")
                if (resultCode != Activity.RESULT_OK) {
                    ForegroundService.stopService(context)
                }
                return true
            }

            if (resultCode == Activity.RESULT_OK) {

                ForegroundService.startService(context, mTitle, mMessage)
                val intentConnection = Intent(context, ForegroundService::class.java)

                serviceConnection = object : ServiceConnection {

                    override fun onServiceConnected(name: ComponentName?, service: IBinder?) {

                        beginCapture(resultCode, data)
                    }

                    override fun onServiceDisconnected(name: ComponentName?) {
                    }
                }

                val isBound = context.bindService(intentConnection, serviceConnection!!, Activity.BIND_AUTO_CREATE)
                if (!isBound) {
                    ForegroundService.stopService(context)
                    completePendingResult(false)
                }

            } else {
                ForegroundService.stopService(context)
                completePendingResult(false)
            }
            return true
        }
        return false
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val appContext = pluginBinding!!.applicationContext

        when (call.method) {
            "startRecordScreen" -> {
                if (pendingResult != null) {
                    result.error(
                        "already_pending",
                        "A screen recording request is already pending.",
                        null
                    )
                    return
                }

                try {
                    pendingResult = result
                    val title = call.argument<String?>("title")
                    val message = call.argument<String?>("message")

                    if (!title.isNullOrEmpty()) {
                        mTitle = title
                    }

                    if (!message.isNullOrEmpty()) {
                        mMessage = message
                    }

                    val metrics = DisplayMetrics()

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val display = activityBinding!!.activity.display
                        display?.getRealMetrics(metrics)
                    } else {
                        @SuppressLint("NewApi")
                        val defaultDisplay = appContext.display
                        defaultDisplay?.getMetrics(metrics)
                    }
                    mScreenDensity = metrics.densityDpi
                    calculateResolution(metrics)
                    videoName = call.argument<String?>("name")
                    recordAudio = call.argument<Boolean?>("audio")

                    val permissionIntent = mProjectionManager.createScreenCaptureIntent()
                    ActivityCompat.startActivityForResult(
                        activityBinding!!.activity,
                        permissionIntent,
                        SCREEN_RECORD_REQUEST_CODE,
                        null
                    )

                } catch (e: Exception) {
                    println("Error onMethodCall startRecordScreen")
                    println(e.message)
                    pendingResult = null
                    result.success(false)
                }
            }
            "stopRecordScreen" -> {
                try {
                    serviceConnection?.let {
                        try { appContext.unbindService(it) } catch (_: Exception) {}
                    }
                    serviceConnection = null
                    stopRecordScreen() // đóng file đúng cách (an toàn nếu hệ thống đã dừng ghi trước đó)
                    ForegroundService.stopService(appContext)
                    // file rỗng/không tồn tại = ghi thất bại -> trả "" để app báo lỗi đúng, không gửi file rỗng
                    val f = File(mFileName ?: "")
                    if (f.exists() && f.length() > 0L) {
                        result.success(mFileName)
                    } else {
                        Log.e("ScreenRecordingPlugin", "file ghi ra rỗng hoặc không tồn tại: $mFileName")
                        result.success("")
                    }
                } catch (e: Exception) {
                    result.success("")
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun calculateResolution(metrics: DisplayMetrics) {

        mDisplayHeight = metrics.heightPixels
        mDisplayWidth = metrics.widthPixels

        var maxRes = 1280.0;
        if (metrics.scaledDensity >= 3.0f) {
            maxRes = 1920.0;
        }
        if (metrics.widthPixels > metrics.heightPixels) {
            var rate = metrics.widthPixels / maxRes

            if (rate > 1.5) {
                rate = 1.5
            }
            mDisplayWidth = maxRes.toInt()
            mDisplayHeight = (metrics.heightPixels / rate).toInt()
            println("Rate : $rate")
        } else {
            var rate = metrics.heightPixels / maxRes
            if (rate > 1.5) {
                rate = 1.5
            }
            mDisplayHeight = maxRes.toInt()
            mDisplayWidth = (metrics.widthPixels / rate).toInt()
            println("Rate : $rate")
        }

        println("Scaled Density")
        println(metrics.scaledDensity)
        println("Original Resolution ")
        println(metrics.widthPixels.toString() + " x " + metrics.heightPixels)
        println("Calcule Resolution ")
        println("$mDisplayWidth x $mDisplayHeight")
    }

    // Chuẩn bị bộ ghi (CHƯA start): start chỉ sau khi đã tạo màn hình ảo, như mẫu chuẩn của Android.
    private fun prepareRecorder(): Boolean {
        try {
            try { mMediaRecorder?.release() } catch (_: Exception) {}
            mMediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(pluginBinding!!.applicationContext)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            val ctx = pluginBinding!!.applicationContext
            var dir: String? = null
            if (Environment.getExternalStorageState() == Environment.MEDIA_MOUNTED) {
                dir = ctx.externalCacheDir?.absolutePath
            }
            if (dir == null) {
                dir = ctx.cacheDir.absolutePath
            }
            mFileName = "$dir/$videoName.mp4"
            try { File(mFileName!!).delete() } catch (_: Exception) {}

            // kích thước chẵn (bộ mã hoá H264 yêu cầu)
            val w = mDisplayWidth and 1.inv()
            val h = mDisplayHeight and 1.inv()

            mMediaRecorder?.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            if (recordAudio == true) {
                mMediaRecorder?.setAudioSource(MediaRecorder.AudioSource.MIC)
                mMediaRecorder?.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                mMediaRecorder?.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            } else {
                mMediaRecorder?.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            }
            mMediaRecorder?.setOutputFile(mFileName)
            mMediaRecorder?.setVideoSize(w, h)
            mMediaRecorder?.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            mMediaRecorder?.setVideoEncodingBitRate(5 * w * h)
            mMediaRecorder?.setVideoFrameRate(30)
            mMediaRecorder?.prepare()
            recorderFinalized = false
            return true
        } catch (e: Exception) {
            Log.e("ScreenRecordingPlugin", "prepareRecorder lỗi: $e")
            return false
        }
    }

    // Trình tự đúng (Android 14+/vivo): dịch vụ đã foreground (onCreate) -> getMediaProjection -> registerCallback ->
    // tạo màn hình ảo -> mới start bộ ghi. Lỗi ở bước nào cũng dọn sạch và trả false để app biết.
    private fun beginCapture(resultCode: Int, data: Intent?) {
        try {
            if (data == null) throw IllegalStateException("không có dữ liệu cấp quyền")
            if (!prepareRecorder()) throw IllegalStateException("không chuẩn bị được bộ ghi")
            mMediaProjectionCallback = MediaProjectionCallback()
            mMediaProjection = mProjectionManager.getMediaProjection(resultCode, data)
            if (mMediaProjection == null) throw IllegalStateException("getMediaProjection trả null")
            mMediaProjection?.registerCallback(mMediaProjectionCallback!!, Handler(Looper.getMainLooper()))
            mVirtualDisplay = createVirtualDisplay()
            if (mVirtualDisplay == null) throw IllegalStateException("không tạo được màn hình ảo")
            mMediaRecorder?.start()
            completePendingResult(true)
        } catch (e: Throwable) {
            Log.e("ScreenRecordingPlugin", "beginCapture lỗi: $e")
            try { mMediaRecorder?.reset(); mMediaRecorder?.release() } catch (_: Exception) {}
            mMediaRecorder = null
            recorderFinalized = true
            try { stopScreenSharing() } catch (_: Exception) {}
            try { mMediaProjection?.stop() } catch (_: Exception) {}
            mMediaProjection = null
            try { serviceConnection?.let { pluginBinding!!.applicationContext.unbindService(it) } } catch (_: Exception) {}
            serviceConnection = null
            ForegroundService.stopService(pluginBinding!!.applicationContext)
            completePendingResult(false)
        }
    }

    // Đóng file ghi đúng cách: stop() mới ghi phần "moov" cuối file; nếu chỉ reset() thì file KHÔNG phát được.
    @Synchronized
    private fun finalizeRecorder() {
        if (recorderFinalized) return
        recorderFinalized = true
        try {
            mMediaRecorder?.stop()
            println("stopRecordScreen success")
        } catch (e: Exception) {
            Log.e("ScreenRecordingPlugin", "MediaRecorder.stop lỗi: $e")
        }
        try { mMediaRecorder?.reset() } catch (_: Exception) {}
        try { mMediaRecorder?.release() } catch (_: Exception) {}
        mMediaRecorder = null
    }

    private fun stopRecordScreen() {
        try {
            finalizeRecorder()
        } finally {
            stopScreenSharing()
        }
    }

    private fun createVirtualDisplay(): VirtualDisplay? {
        try {
            return mMediaProjection?.createVirtualDisplay(
                "MainActivity", mDisplayWidth, mDisplayHeight, mScreenDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, mMediaRecorder?.surface, null, null
            )
        } catch (e: Exception) {
            println("createVirtualDisplay err")
            println(e.message)
            return null
        }
    }

    private fun stopScreenSharing() {
        if (mVirtualDisplay != null) {
            mVirtualDisplay?.release()
            if (mMediaProjection != null && mMediaProjectionCallback != null) {
                mMediaProjection?.unregisterCallback(mMediaProjectionCallback!!)
                mMediaProjection?.stop()
                mMediaProjection = null
            }
            Log.d("TAG", "MediaProjection Stopped")
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = binding;
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding;
        val channel = MethodChannel(pluginBinding!!.binaryMessenger, "flutter_screen_recording")
        channel.setMethodCallHandler(this)
        activityBinding!!.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding;
    }

    override fun onDetachedFromActivity() {}

    inner class MediaProjectionCallback : MediaProjection.Callback() {
        override fun onStop() {
            // Hệ thống dừng chia sẻ màn hình (VD HyperOS/Android 14+): phải ĐÓNG file chứ không reset (reset làm file hỏng)
            Log.w("ScreenRecordingPlugin", "MediaProjection.onStop: hệ thống đã dừng ghi")
            finalizeRecorder()
            mMediaProjection = null
            stopScreenSharing()
        }
    }
}
