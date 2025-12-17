# Keep OkHttp classes
-keepattributes Signature
-keepattributes *Annotation*
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep plugin classes
-keep class com.ashrafksalim.flutter_auto_echo_cancellation_websocket.** { *; }
