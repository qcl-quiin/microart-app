package com.isvisoft.flutter_screen_recording

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

// MicroAct (11/10/2026): bản sửa cho vivo/Android 14+.
// Lỗi gốc: dịch vụ chỉ lên foreground trong onStartCommand (bất đồng bộ), còn plugin lại gọi getMediaProjection()
// ngay khi bind xong => trên máy chạy nhanh thì kịp, vivo (Android 16) thì chưa => ghi ra file rỗng.
// Sửa: lên foreground NGAY trong onCreate, kèm kiểu mediaProjection (bind chỉ xong SAU onCreate).
class ForegroundService : Service() {
    private val CHANNEL_ID = "ForegroundService Kotlin"

    companion object {
        private const val TAG = "ScreenRecordingPlugin"
        const val ACTION_STOP = "com.foregroundservice.ACTION_STOP"

        fun startService(context: Context, title: String, message: String) {
            try {
                val startIntent = Intent(context, ForegroundService::class.java)
                startIntent.putExtra("messageExtra", message)
                startIntent.putExtra("titleExtra", title)
                ContextCompat.startForegroundService(context, startIntent)
            } catch (err: Exception) {
                Log.e(TAG, "startService err: $err")
            }
        }

        fun stopService(context: Context) {
            try {
                val stopIntent = Intent(context, ForegroundService::class.java).setAction(ACTION_STOP)
                context.startService(stopIntent)
            } catch (err: Exception) {
                Log.e(TAG, "stopService err: $err")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        goForeground("MicroAct", "")
    }

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra("titleExtra") ?: "MicroAct"
        val message = intent?.getStringExtra("messageExtra") ?: ""
        goForeground(title, message) // cập nhật nội dung thông báo (và bảo đảm đã lên foreground)
        return START_NOT_STICKY
    }

    private fun goForeground(title: String, message: String) {
        try {
            createNotificationChannel()
            val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
            val pendingIntent = PendingIntent.getActivity(
                this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(message)
                .setSmallIcon(android.R.drawable.presence_video_online)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else {
                startForeground(1, notification)
            }
        } catch (e: Throwable) {
            Log.e(TAG, "goForeground lỗi: $e")
        }
    }

    override fun onBind(intent: Intent): IBinder {
        return Binder()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID, "Foreground Service Channel", NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }
}
