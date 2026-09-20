# Flutter engine and registered plugins are reached through generated/native entry points.
-keep class io.flutter.** { *; }
-keep class dev.flutter.** { *; }
-dontwarn javax.annotation.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
