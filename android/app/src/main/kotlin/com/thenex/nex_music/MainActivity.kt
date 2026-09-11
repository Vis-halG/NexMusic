package com.thenex.nex_music

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.thenex.nexmusic/media_tools"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "extractAndTrimAudio") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val source = call.argument<String>("source")
                val startMs = call.argument<Number>("startMs")?.toLong() ?: 0L
                val endMs = call.argument<Number>("endMs")?.toLong() ?: Long.MAX_VALUE
                if (source.isNullOrBlank() || endMs <= startMs) {
                    result.error("INVALID_RANGE", "Choose a valid file and trim range.", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val path = extractAndTrim(source, startMs, endMs)
                        runOnUiThread { result.success(path) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("MEDIA_PROCESSING_FAILED", error.message, null)
                        }
                    }
                }.start()
            }
    }

    /**
     * Copies an AAC-compatible track into M4A, or copies complete MP3 frames
     * into a trimmed MP3. MediaMuxer cannot put audio/mpeg into MP4, which was
     * the cause of "Failed to add the track to the muxer" for normal MP3s.
     * No network downloader is used: [source] must be a user-selected local
     * file or Android content URI for media they are allowed to process.
     */
    private fun extractAndTrim(source: String, startMs: Long, endMs: Long): String {
        val extractor = MediaExtractor()
        if (source.startsWith("content://")) {
            contentResolver.openAssetFileDescriptor(Uri.parse(source), "r")?.use { descriptor ->
                extractor.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
            } ?: error("The selected file could not be opened.")
        } else {
            extractor.setDataSource(if (source.startsWith("file://")) Uri.parse(source).path!! else source)
        }

        var audioTrack = -1
        var audioFormat: MediaFormat? = null
        for (index in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(index)
            val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
            if (mime.startsWith("audio/")) {
                audioTrack = index
                audioFormat = format
                break
            }
        }
        if (audioTrack < 0 || audioFormat == null) {
            extractor.release()
            error("This file does not contain a supported audio track.")
        }

        val mime = audioFormat.getString(MediaFormat.KEY_MIME).orEmpty()
        if (mime == "audio/mpeg") {
            return trimMp3(extractor, audioTrack, audioFormat, startMs, endMs)
        }

        val exportDir = File(cacheDir, "nexmusic_exports").apply { mkdirs() }
        val output = File(exportDir, "${UUID.randomUUID()}.m4a")
        val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val outputTrack = muxer.addTrack(audioFormat)
        extractor.selectTrack(audioTrack)
        extractor.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
        muxer.start()

        val maxSize = if (audioFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
            audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE).coerceAtLeast(256 * 1024)
        } else 1024 * 1024
        val buffer = ByteBuffer.allocateDirect(maxSize)
        val info = MediaCodec.BufferInfo()
        val startUs = startMs * 1000
        val endUs = endMs * 1000
        while (true) {
            val sampleTime = extractor.sampleTime
            if (sampleTime < 0 || sampleTime > endUs) break
            buffer.clear()
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) break
            if (sampleTime >= startUs) {
                info.set(0, size, sampleTime - startUs, extractor.sampleFlags)
                muxer.writeSampleData(outputTrack, buffer, info)
            }
            extractor.advance()
        }
        muxer.stop()
        muxer.release()
        extractor.release()
        return output.absolutePath
    }

    private fun trimMp3(
        extractor: MediaExtractor,
        audioTrack: Int,
        audioFormat: MediaFormat,
        startMs: Long,
        endMs: Long,
    ): String {
        val exportDir = File(cacheDir, "nexmusic_exports").apply { mkdirs() }
        val output = File(exportDir, "${UUID.randomUUID()}.mp3")
        val maxSize = if (audioFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
            audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE).coerceAtLeast(256 * 1024)
        } else 1024 * 1024
        val buffer = ByteBuffer.allocateDirect(maxSize)
        val startUs = startMs * 1000
        val endUs = endMs * 1000

        try {
            extractor.selectTrack(audioTrack)
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            FileOutputStream(output).use { stream ->
                while (true) {
                    val sampleTime = extractor.sampleTime
                    if (sampleTime < 0 || sampleTime > endUs) break
                    buffer.clear()
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break
                    if (sampleTime >= startUs) {
                        val frame = ByteArray(size)
                        buffer.position(0)
                        buffer.limit(size)
                        buffer.get(frame)
                        stream.write(frame)
                    }
                    extractor.advance()
                }
            }
        } finally {
            extractor.release()
        }
        if (output.length() == 0L) {
            output.delete()
            error("The selected MP3 range contains no audio.")
        }
        return output.absolutePath
    }
}
