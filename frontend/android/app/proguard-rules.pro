# R8 rules for the release build.
#
# R8 is Android's code shrinker. It runs on `flutter build apk --release` and
# `flutter build appbundle --release` and on nothing else - debug builds skip it entirely, which is
# why a bug caused by these rules cannot be reproduced with `make dev`. Flutter's own Gradle plugin
# turns it on (`isMinifyEnabled = true`) and picks this file up automatically because of its name
# and location, so there is nothing to wire up in build.gradle.kts.
#
# What R8 does, and why it needs telling:
#
#   1. shrinking     - deletes every class and method that nothing appears to call
#   2. obfuscation   - renames what is left to a, b, c (smaller, and harder to read)
#   3. optimization  - inlines, merges, removes dead branches
#
# It decides "nothing calls this" by reading the compiled code. That works for ordinary Java calls
# and fails completely for anything looked up **by name at run time** - JNI, reflection,
# `Class.forName`. To R8 those classes look unused, so it deletes them or renames them out from
# under the code that was going to ask for them by their original name.
#
# The failure is always the same shape: the debug build works forever, the release build crashes or
# comes up blank, and the stack trace names a class called `a`. Every rule below exists to prevent
# one instance of that.

# ---------------------------------------------------------------------------------------------
# Yandex MapKit - the reason this file exists
# ---------------------------------------------------------------------------------------------
#
# MapKit is a native C++ renderer with a thin Java layer over it. The C++ side reaches back into
# Java through JNI, which looks up classes, methods and fields **by their string names**. R8 sees a
# Java class nothing in the Java code calls and deletes it; the native side then asks for a name
# that no longer exists and the map comes up blank or the app dies on the first map frame.
#
# There is no narrower version of this rule that is safe. We cannot know which of MapKit's classes
# its own native code names, so the whole package is kept.
-keep class com.yandex.** { *; }
-keep interface com.yandex.** { *; }
-dontwarn com.yandex.**

# MapKit's Java layer references optional Android and Google classes that are not on our classpath
# (it supports configurations we do not use). Without these, R8 stops on a warning about a class it
# was never going to need.
-dontwarn com.google.android.gms.**
-dontwarn com.huawei.**
-dontwarn javax.annotation.**

# ---------------------------------------------------------------------------------------------
# JNI in general
# ---------------------------------------------------------------------------------------------
#
# Any method marked `native` is implemented in C, and the C side finds it by name. Renaming the
# Java side breaks the link silently - the method exists, nothing can call it.
-keepclasseswithmembernames class * {
    native <methods>;
}

# ---------------------------------------------------------------------------------------------
# flutter_secure_storage
# ---------------------------------------------------------------------------------------------
#
# Where the JWT, role, name and phone live. It goes through AndroidX Security, which builds its
# crypto objects reflectively from class names in a config - so the classes are never mentioned in
# code R8 can follow. If R8 strips them the app compiles, installs, and then cannot read its own
# stored session: every user is silently logged out on the release build only.
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# ---------------------------------------------------------------------------------------------
# Kept on purpose, small cost
# ---------------------------------------------------------------------------------------------
#
# Enum values are read by name by `valueOf`, which is reflection. Flutter plugins pass enums across
# the method channel as strings and rebuild them this way.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelable's CREATOR field is found reflectively by the OS, never by our code.
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Annotations are metadata - R8 discards them by default, and libraries that read their own
# annotations at run time then find nothing.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Keep line numbers in crash reports. Without this a production stack trace is a list of method
# names with no lines, which is the difference between "we know the bug" and "we know the file".
# SourceFile is renamed rather than kept, so it leaks no paths.
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
