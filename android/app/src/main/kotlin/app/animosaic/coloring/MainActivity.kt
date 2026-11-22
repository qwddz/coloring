package app.animosaic.coloring

import android.graphics.Rect
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Canvas rects (logical pixels) kept off the edge swipe "back" gesture,
        // from lib/app/back_gesture_exclusion.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.animosaic.coloring/gestures")
            .setMethodCallHandler { call, result ->
                if (call.method != "setExclusionRects") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val density = resources.displayMetrics.density
                    window.decorView.systemGestureExclusionRects =
                        (call.arguments as List<*>).map { item ->
                            val v = (item as List<*>).map { (it as Number).toDouble() * density }
                            Rect(v[0].toInt(), v[1].toInt(), v[2].toInt(), v[3].toInt())
                        }
                }
                result.success(null)
            }
    }
}
