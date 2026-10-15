# Flutter plugin entry points are registered by GeneratedPluginRegistrant.
# Keep notification models serialized by Gson and their generic signatures.
-keepattributes Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations,AnnotationDefault
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keep class com.dexterous.flutterlocalnotifications.RuntimeTypeAdapterFactory { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver { *; }
# Firebase, Play, Billing, Mobile Ads, Meta and Flutter ship consumer rules.
# Do not keep their entire packages: R8 must be able to optimize unused code.

# Native Flutter engine entry points and optional deferred-component APIs.
-keep class io.flutter.** { *; }
-dontwarn javax.annotation.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Notification deserialization uses anonymous Gson TypeToken subclasses.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
