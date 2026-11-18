package com.humanifest.phonopticon

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.humanifest.phonopticon/export"
    private val shareRequestCode = 42017
    private var pendingExportResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "shareBundle") {
                    val json = call.argument<String>("json")
                    val filename = call.argument<String>("filename")
                    if (json == null || filename == null) {
                        result.error("invalid_arguments", "JSON and filename are required", null)
                    } else {
                        try {
                            val dir = File(cacheDir, "phonopticon-export")
                            dir.mkdirs()
                            val file = File(dir, filename)
                            FileOutputStream(file).use { it.write(json.toByteArray(Charsets.UTF_8)) }
                            val uri: Uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file,
                            )
                            val share = Intent(Intent.ACTION_SEND).apply {
                                type = "application/json"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                putExtra(Intent.EXTRA_TITLE, filename)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            pendingExportResult = result
                            startActivityForResult(
                                Intent.createChooser(share, "Save or share trial bundle"),
                                shareRequestCode,
                            )
                        } catch (error: Throwable) {
                            result.success(mapOf("status" to "error", "detail" to error.message))
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == shareRequestCode) {
            val status = if (resultCode == RESULT_OK) "shared" else "cancelled"
            pendingExportResult?.success(mapOf("status" to status, "detail" to ""))
            pendingExportResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
