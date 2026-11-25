package com.humanifest.phonopticon

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent

class MainActivity : FlutterActivity() {
    private val channelName = "com.humanifest.phonopticon/export"
    private val shareRequestCode = 42017
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportJson: String? = null

    override fun onDestroy() {
        val result = pendingExportResult
        pendingExportResult = null
        pendingExportJson = null
        result?.success(
            mapOf(
                "status" to "error",
                "detail" to "Export interrupted because the app activity was recreated. Please retry.",
            ),
        )
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "shareBundle") {
                    val json = call.argument<String>("json")
                    val filename = call.argument<String>("filename")
                    if (json == null || filename == null) {
                        result.error("invalid_arguments", "JSON and filename are required", null)
                    } else if (pendingExportResult != null) {
                        result.success(
                            mapOf("status" to "error", "detail" to "An export is already open"),
                        )
                    } else {
                        try {
                            val createDocument = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, filename)
                            }
                            pendingExportResult = result
                            pendingExportJson = json
                            startActivityForResult(
                                createDocument,
                                shareRequestCode,
                            )
                        } catch (error: Exception) {
                            pendingExportResult = null
                            pendingExportJson = null
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
            val result = pendingExportResult
            pendingExportResult = null
            val json = pendingExportJson
            pendingExportJson = null
            if (resultCode != RESULT_OK) {
                result?.success(mapOf("status" to "cancelled"))
                return
            }
            try {
                val uri = data?.data
                    ?: throw IllegalStateException("Document picker returned no destination")
                val content = json ?: throw IllegalStateException("Export data unavailable")
                contentResolver.openOutputStream(uri, "wt").use { stream ->
                    val output = stream ?: throw IllegalStateException("Cannot open selected document")
                    output.write(content.toByteArray(Charsets.UTF_8))
                }
                result?.success(mapOf("status" to "saved"))
            } catch (error: Exception) {
                result?.success(mapOf("status" to "error", "detail" to error.message))
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
