package com.example.spendsense

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Narrow platform bridge for OTA updates.
 *
 * Only three capabilities live here, because Flutter cannot do them safely:
 *  - read an APK archive's package name and signing certificate;
 *  - query/route the "install unknown apps" permission;
 *  - hand a verified APK to the system package installer.
 *
 * No installation happens without the user's explicit action in the system UI.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "spendsense/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApkInfo" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "Missing APK path", null)
                            return@setMethodCallHandler
                        }
                        val info = readApkInfo(path)
                        if (info == null) {
                            result.error("unreadable", "Could not read the APK archive", null)
                        } else {
                            result.success(info)
                        }
                    }
                    "canRequestPackageInstalls" -> {
                        result.success(canRequestPackageInstalls())
                    }
                    "openInstallPermissionSettings" -> {
                        try {
                            openInstallPermissionSettings()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("settings_unavailable", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "Missing APK path", null)
                            return@setMethodCallHandler
                        }
                        result.success(launchInstaller(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readApkInfo(path: String): Map<String, Any?>? {
        return try {
            val pm = packageManager
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_SIGNATURES
            }
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(flags.toLong()))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageArchiveInfo(path, flags)
            } ?: return null

            val certBytes: ByteArray? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
            } else {
                @Suppress("DEPRECATION")
                info.signatures?.firstOrNull()?.toByteArray()
            }
            val digest = certBytes?.let { bytes ->
                MessageDigest.getInstance("SHA-256").digest(bytes)
                    .joinToString("") { b -> "%02x".format(b) }
            }

            mapOf(
                "packageName" to info.packageName,
                "signerSha256" to digest,
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
    }

    private fun launchInstaller(path: String): String {
        val updatesDir = File(cacheDir, "updates").canonicalFile
        val apk = File(path).canonicalFile
        if (!apk.path.startsWith(updatesDir.path + File.separator)) {
            return "untrusted_path"
        }
        if (!apk.exists()) {
            return "missing_file"
        }
        if (!canRequestPackageInstalls()) {
            return "permission_required"
        }
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apk,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "started"
        } catch (e: Exception) {
            "error"
        }
    }
}
