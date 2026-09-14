# ExoPlayer's streaming modules are excluded in build.gradle.kts. just_audio
# and video_player only use them for .mpd, .m3u8 and rtsp:// sources, which
# nexMusic refuses before playback.
-dontwarn androidx.media3.exoplayer.dash.**
-dontwarn androidx.media3.exoplayer.hls.**
-dontwarn androidx.media3.exoplayer.rtsp.**
-dontwarn androidx.media3.exoplayer.smoothstreaming.**
