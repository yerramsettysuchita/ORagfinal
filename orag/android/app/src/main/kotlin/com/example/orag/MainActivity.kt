package com.example.orag

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.PyObject
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import android.util.Log

class MainActivity : FlutterActivity() {
	private val CHANNEL = "orag"
	@Volatile
	private var apiModule: PyObject? = null

	private fun ensureApiModule(): PyObject {
		apiModule?.let { return it }
		synchronized(this) {
			apiModule?.let { return it }
			if (!Python.isStarted()) {
				Python.start(AndroidPlatform(this))
			}
			val module = Python.getInstance().getModule("api")
			apiModule = module
			return module
		}
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				if (call.method == "initPython") {
					val modelPath = call.argument<String>("model_path") ?: ""

					Thread {
						try {
							ensureApiModule().callAttr("init_with_path", modelPath)
							runOnUiThread {
								result.success(true)
							}
							Log.i("ORAG", "Python init completed: $modelPath")
						} catch (e: Exception) {
							runOnUiThread {
								result.error("ERROR", e.message, null)
							}
							Log.e("ORAG", "Python init failed", e)
						}
					}.start()
				} else if (call.method == "chat") {
					val query = call.argument<String>("query") ?: ""

					Thread {
						try {
							val response = ensureApiModule().callAttr("chat", query)

							runOnUiThread {
								result.success(response.toString())
							}
						} catch (e: Exception) {
							runOnUiThread {
								result.error("ERROR", e.message, null)
							}
						}
					}.start()
				} else {
					result.notImplemented()
				}
			}
	}
}
