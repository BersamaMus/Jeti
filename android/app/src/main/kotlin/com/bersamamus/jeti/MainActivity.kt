package com.bersamamus.jeti

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * What Jeti needs from Android that Flutter doesn't give it: which version of
 * an app is installed, opening and removing it, and installing a downloaded
 * APK. lib/services/android_host.dart is the other end of the channel.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "jeti/android"
        const val INSTALL_STATUS = "com.bersamamus.jeti.INSTALL_STATUS"
    }

    /** The install waiting for Android's answer. Only one runs at a time. */
    private var pendingInstall: MethodChannel.Result? = null

    /** Its session, once Android has shown the confirm screen for it. */
    private var confirmingSession: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(INSTALL_STATUS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(installStatus, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(installStatus, filter)
        }
    }

    override fun onDestroy() {
        unregisterReceiver(installStatus)
        finishInstall("failed", "Jeti was closed")
        super.onDestroy()
    }

    /**
     * Back from the confirm screen. Android doesn't always answer when it's
     * dismissed (Back, or Home then Jeti), so after a moment for an answer
     * that's on its way, an install whose session isn't being worked on
     * counts as cancelled.
     */
    override fun onResume() {
        super.onResume()
        val id = confirmingSession ?: return
        window.decorView.postDelayed({
            if (pendingInstall == null || confirmingSession != id) return@postDelayed
            val installer = packageManager.packageInstaller
            if (installer.getSessionInfo(id)?.isActive == true) return@postDelayed
            try {
                installer.abandonSession(id)
            } catch (_: Exception) {
                // Already gone.
            }
            finishInstall("cancelled", null)
        }, 2000)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val pkg = call.argument<String>("package")
            when (call.method) {
                "installedVersion" -> result.success(installedVersion(pkg!!))
                "open" -> result.success(open(pkg!!))
                "uninstall" -> {
                    startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")))
                    result.success(null)
                }
                "appInfo" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg")))
                    result.success(null)
                }
                "canInstall" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                )
                "openInstallSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    )
                    result.success(null)
                }
                "install" -> install(call.argument<String>("path")!!, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun installedVersion(pkg: String): String? = try {
        // An app that's installed but has no version name still counts as installed.
        packageManager.getPackageInfo(pkg, 0).versionName ?: ""
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    private fun open(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        startActivity(intent)
        return true
    }

    /**
     * Hands the APK at [path] to Android's installer, which asks the person to
     * confirm (unless it's an update to an app Jeti installed, on Android 12
     * and up). Answers with a status once Android has installed it or hasn't.
     */
    private fun install(path: String, result: MethodChannel.Result) {
        if (pendingInstall != null) {
            result.success(mapOf("status" to "busy"))
            return
        }
        pendingInstall = result
        val file = File(path)
        Thread {
            val installer = packageManager.packageInstaller
            var id: Int? = null
            try {
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                params.setSize(file.length())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                }
                val sessionId = installer.createSession(params)
                id = sessionId
                installer.openSession(sessionId).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("base.apk", 0, file.length()).use { output ->
                            input.copyTo(output)
                            session.fsync(output)
                        }
                    }
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                    val status = PendingIntent.getBroadcast(
                        this, sessionId, Intent(INSTALL_STATUS).setPackage(packageName), flags
                    )
                    session.commit(status.intentSender)
                }
            } catch (e: Exception) {
                // Nothing reached Android, so its half-written copy goes.
                id?.let {
                    try {
                        installer.abandonSession(it)
                    } catch (_: Exception) {
                    }
                }
                runOnUiThread { finishInstall("failed", e.message) }
            } finally {
                // Android has its own copy now.
                file.delete()
            }
        }.start()
    }

    private val installStatus = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    // Android's "Do you want to install this app?" screen.
                    val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    } else {
                        @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
                    }
                    if (confirm == null) {
                        finishInstall("failed", message)
                    } else {
                        val id = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
                        confirmingSession = if (id == -1) null else id
                        startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                }
                PackageInstaller.STATUS_SUCCESS -> finishInstall("installed", null)
                PackageInstaller.STATUS_FAILURE_ABORTED -> finishInstall("cancelled", message)
                PackageInstaller.STATUS_FAILURE_BLOCKED -> finishInstall("blocked", message)
                PackageInstaller.STATUS_FAILURE_CONFLICT -> finishInstall("conflict", message)
                PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> finishInstall("incompatible", message)
                PackageInstaller.STATUS_FAILURE_INVALID -> finishInstall("invalid", message)
                PackageInstaller.STATUS_FAILURE_STORAGE -> finishInstall("storage", message)
                else -> finishInstall("failed", message)
            }
        }
    }

    private fun finishInstall(status: String, message: String?) {
        pendingInstall?.success(mapOf("status" to status, "message" to message))
        pendingInstall = null
        confirmingSession = null
    }
}
