# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# WebView
-keep class android.webkit.** { *; }

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}

# OkHttp (http package)
-dontwarn okhttp3.**
-dontwarn okio.**

# Kotlin
-dontwarn kotlin.**
-keep class kotlin.** { *; }
