# Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# TensorFlow Lite — keep all classes including GPU delegate
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-keep class org.tensorflow.lite.nnapi.** { *; }
-dontwarn org.tensorflow.lite.**
-dontwarn org.tensorflow.**

# TFLite Select TF Ops
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

# MediaPipe / Google ML Kit
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Cactus / native FFI — keep JNI entry points
-keepclasseswithmembernames class * {
    native <methods>;
}

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Hive
-keep class com.hivedb.** { *; }
-dontwarn com.hivedb.**
