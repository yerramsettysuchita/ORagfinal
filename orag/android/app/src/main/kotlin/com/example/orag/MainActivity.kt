package com.example.orag

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.PyObject
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import android.util.Log

class MainActivity : FlutterActivity() {
	private val CHANNEL = "orag"
	private val STREAM_CHANNEL = "orag_stream"

	@Volatile
	private var apiModule: PyObject? = null

	@Volatile
	private var streamSink: EventChannel.EventSink? = null

	/**
	 * Called from Python (via Chaquopy invoke) for each generated token.
	 * Forwards the token to the Flutter EventChannel sink on the UI thread.
	 */
	fun onStreamToken(token: String) {
		runOnUiThread {
			streamSink?.success(token)
		}
	}

	private fun ensureApiModule(): PyObject {
		apiModule?.let { return it }
		synchronized(this) {
			apiModule?.let { return it }
			if (!Python.isStarted()) {
				Python.start(AndroidPlatform(this))
			}

			// Inject Android paths into llm module before any init runs.
			// mActivity is not accessible from Python in this Flutter/Chaquopy
			// context, so we push nativeLibraryDir from Kotlin directly.
			try {
				val llm = Python.getInstance().getModule("llm")
				val nativeLibDir = applicationInfo.nativeLibraryDir
				val filesDir = filesDir.absolutePath
				llm.callAttr("set_android_paths", nativeLibDir, filesDir)
				Log.i("ORAG", "Injected nativeLibraryDir=$nativeLibDir, filesDir=$filesDir")
			} catch (e: Exception) {
				Log.w("ORAG", "Failed to inject Android paths", e)
			}

			val module = Python.getInstance().getModule("api")
			apiModule = module
			return module
		}
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		// --- EventChannel for streaming tokens ---
		EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL)
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					streamSink = events
					Log.d("ORAG", "Stream listener attached")
				}
				override fun onCancel(arguments: Any?) {
					streamSink = null
					Log.d("ORAG", "Stream listener cancelled")
				}
			})

		// --- MethodChannel for RPC calls ---
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

				} else if (call.method == "chatStream") {
					val query = call.argument<String>("query") ?: ""

					Thread {
						try {
							val api = ensureApiModule()

							// Pass a Kotlin method reference to Python.
							// Chaquopy makes it callable via .invoke() on
							// the Python side.
							val response = api.callAttr(
								"chat_stream", query, this@MainActivity::onStreamToken
							)

							runOnUiThread {
								streamSink?.success("__STREAM_END__")
								result.success(response.toString())
							}
						} catch (e: Exception) {
							runOnUiThread {
								streamSink?.success("__STREAM_END__")
								result.error("ERROR", e.message, null)
							}
							Log.e("ORAG", "chatStream failed", e)
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
				} else if (call.method == "stop") {
					Thread {
						try {
							ensureApiModule().callAttr("stop_generation")
							runOnUiThread { result.success(true) }
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
