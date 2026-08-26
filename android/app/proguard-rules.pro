# Hoza Download — R8 rules for the release build.
#
# Flutter's own rules ship with the Gradle plugin; these cover the parts of the
# app R8 cannot see are in use because they are reached from the manifest or
# across the platform channel boundary.

# The activity and service are named in AndroidManifest.xml, and the channel
# classes are constructed reflectively by neither R8 nor Flutter — keeping the
# whole package is cheap and removes a class of release-only crashes.
-keep class com.hoza.download.** { *; }

# Flutter's embedding entry points.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# sqflite and path_provider reach their Java classes through generated
# registrants; their own consumer rules cover the rest.
-keep class com.tekartik.sqflite.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }

# R8 warns about optional desugaring classes these libraries reference but
# never call on Android.
-dontwarn org.xmlpull.v1.**
-dontwarn javax.annotation.**

# Flutter's embedding references Google Play's split-install (deferred
# component) classes so that apps which ship deferred components can use them.
# Hoza ships none and does not depend on the Play Core library, so the classes
# are absent by design; R8 must not treat that as an error.
-dontwarn com.google.android.play.core.**
