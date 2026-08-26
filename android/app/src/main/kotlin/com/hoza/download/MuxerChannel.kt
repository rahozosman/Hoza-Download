package com.hoza.download

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Merges a video-only file and an audio-only file into one playable MP4.
 *
 * Sites that publish adaptive streams keep the tracks in separate files, so a
 * download of the video alone would be silent. [MediaMuxer] is part of Android
 * itself, so this costs no APK size and no re-encoding: the compressed samples
 * are copied across untouched, which is fast and lossless.
 *
 * The work runs off the main thread — a large file would otherwise block the
 * UI — and the result is always posted back on the platform thread, because
 * Flutter requires it.
 */
class MuxerChannel {

    private val worker = Executors.newSingleThreadExecutor()

    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mux" -> {
                    val videoPath = call.argument<String>("video")
                    val audioPath = call.argument<String>("audio")
                    val outputPath = call.argument<String>("output")
                    if (videoPath == null || audioPath == null || outputPath == null) {
                        result.error("bad_arguments", "video, audio and output are required", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        val outcome = runCatching { mux(videoPath, audioPath, outputPath) }
                        // A method result may only be delivered on the platform
                        // thread, and no activity need be on screen for that.
                        main.post { deliver(result, outcome) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun deliver(result: MethodChannel.Result, outcome: Result<Unit>) {
        outcome.fold(
            onSuccess = { result.success(true) },
            onFailure = { error -> result.error("mux_failed", error.message, null) },
        )
    }

    /**
     * Copies every track of [videoPath] and the first audio track of
     * [audioPath] into [outputPath].
     *
     * A partially written output is deleted on failure so a later retry never
     * publishes a truncated file.
     */
    private fun mux(videoPath: String, audioPath: String, outputPath: String) {
        val output = File(outputPath)
        val videoExtractor = MediaExtractor()
        val audioExtractor = MediaExtractor()
        var muxer: MediaMuxer? = null

        try {
            videoExtractor.setDataSource(videoPath)
            audioExtractor.setDataSource(audioPath)

            val videoTrack = selectTrack(videoExtractor, "video/")
                ?: error("No video track in the downloaded file")
            val audioTrack = selectTrack(audioExtractor, "audio/")
                ?: error("No audio track in the downloaded file")

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val videoOut = muxer.addTrack(videoExtractor.getTrackFormat(videoTrack))
            val audioOut = muxer.addTrack(audioExtractor.getTrackFormat(audioTrack))
            muxer.start()

            copy(videoExtractor, muxer, videoOut, bufferSizeFor(videoExtractor, videoTrack))
            copy(audioExtractor, muxer, audioOut, bufferSizeFor(audioExtractor, audioTrack))

            muxer.stop()
        } catch (error: Throwable) {
            output.delete()
            throw error
        } finally {
            runCatching { muxer?.release() }
            runCatching { videoExtractor.release() }
            runCatching { audioExtractor.release() }
        }
    }

    /** Index of the first track whose MIME type starts with [prefix]. */
    private fun selectTrack(extractor: MediaExtractor, prefix: String): Int? {
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME).orEmpty()
            if (mime.startsWith(prefix)) {
                extractor.selectTrack(index)
                return index
            }
        }
        return null
    }

    /**
     * The largest sample the track declares, with a floor for formats that do
     * not declare one. Too small a buffer would truncate a sample.
     */
    private fun bufferSizeFor(extractor: MediaExtractor, track: Int): Int {
        val format = extractor.getTrackFormat(track)
        val declared = if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
            format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
        } else {
            0
        }
        return maxOf(declared, MIN_BUFFER_BYTES)
    }

    private fun copy(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        outputTrack: Int,
        bufferSize: Int,
    ) {
        val buffer = ByteBuffer.allocate(bufferSize)
        val info = MediaCodec.BufferInfo()

        while (true) {
            val read = extractor.readSampleData(buffer, 0)
            if (read < 0) break

            info.offset = 0
            info.size = read
            info.presentationTimeUs = extractor.sampleTime
            info.flags = extractor.sampleFlags

            muxer.writeSampleData(outputTrack, buffer, info)
            extractor.advance()
        }
    }

    private companion object {
        const val CHANNEL = "com.hoza.download/muxer"

        /** 1 MB covers a keyframe of any resolution this app downloads. */
        const val MIN_BUFFER_BYTES = 1 shl 20
    }
}
