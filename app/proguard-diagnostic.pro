# Diagnostic ProGuard rules (minify/shrink enabled, but keep logs + debug info).
# Use this for the `diagnostic` build type to reproduce release issues while
# still being able to see logs and meaningful stack traces.

# Keep debug info for stack traces
-keepattributes SourceFile,LineNumberTable

# Retrofit + reflection need generic signatures/annotations to remain intact.
-keepattributes Signature,RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,AnnotationDefault,EnclosingMethod,InnerClasses

# Preserve Room database annotations and entities
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-keep @androidx.room.Dao class *

# Preserve Retrofit and serialization
-keep class retrofit2.** { *; }
-keep class com.google.gson.** { *; }
-keep class kotlinx.serialization.** { *; }

# Retrofit Kotlin-suspend support needs generic signatures on Continuation.
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.CoroutineContext { *; }

# Kotlinx Serialization (required when minifyEnabled=true)
# The generated **$$serializer classes are discovered reflectively; keep their names.
-keep class **$$serializer { *; }
-keepclassmembers class **$Companion {
    public kotlinx.serialization.KSerializer serializer(...);
}
-keepclassmembers class ** {
    public static kotlinx.serialization.KSerializer serializer(...);
}

# Gson models persisted as JSON (keep field names stable across releases)
-keepclassmembers class com.porarri.yamabikochat.data.remote.OpenAiCompatPreset {
    <fields>;
}
-keepclassmembers class com.porarri.yamabikochat.data.local.SystemPromptPreset {
    <fields>;
}

# Preserve Compose
-keep class androidx.compose.** { *; }

# WebView configuration (if used for math rendering)
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Preserve API model classes structure but obfuscate names
-keep class com.porarri.yamabikochat.data.remote.*Request { *; }
-keep class com.porarri.yamabikochat.data.remote.*Response { *; }

# Markwon markdown rendering library
-keep class io.noties.markwon.** { *; }
-dontwarn io.noties.markwon.**
-dontwarn com.caverock.androidsvg.**
-dontwarn org.commonmark.ext.gfm.**
-dontwarn pl.droidsonroids.gif.**

# Keep the same obfuscation style as release as much as possible
-optimizationpasses 5
-allowaccessmodification
-dontskipnonpubliclibraryclasses
-repackageclasses 'obfuscated'
-obfuscationdictionary dictionary.txt
-classobfuscationdictionary dictionary.txt
-packageobfuscationdictionary dictionary.txt
