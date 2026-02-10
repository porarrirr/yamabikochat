# Security-Enhanced ProGuard Configuration

# Remove all debug logs for release builds
-assumenosideeffects class android.util.Log {
    public static *** v(...);
    public static *** d(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}

# Obfuscate sensitive security classes
-keep class com.porarri.yamabikochat.utils.SecurePreferencesManager {
    public <methods>;
}

# Preserve security-related classes but obfuscate internal methods
-keep class com.porarri.yamabikochat.data.local.SettingsManager {
    public <methods>;
}

# Obfuscate API provider classes while keeping necessary methods
-keep class com.porarri.yamabikochat.data.remote.*Provider {
    public <methods>;
}

# Remove source file information for security
-renamesourcefileattribute ""

# Enable aggressive optimization
-optimizationpasses 5
-allowaccessmodification
-dontskipnonpubliclibraryclasses
-repackageclasses 'obfuscated'

# Keep runtime annotations/generics needed by reflection-based libs (Retrofit/Gson).
# Keep this list consolidated to avoid accidental attribute loss when tweaking rules.
-keepattributes Signature,RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,AnnotationDefault,EnclosingMethod,InnerClasses

# Enhanced security obfuscation
-obfuscationdictionary dictionary.txt
-classobfuscationdictionary dictionary.txt
-packageobfuscationdictionary dictionary.txt

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
