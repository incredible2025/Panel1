# LibVLC's JNI initialisation looks up Java classes, private factory methods,
# callbacks and fields by name, including types not referenced by app code.
# The upstream AAR does not provide consumer rules for these native upcalls.
-keep class org.videolan.libvlc.** { *; }
