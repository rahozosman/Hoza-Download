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
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Merges a video-only file and an audio-only file into one playable file, and
 * re-encodes an audio file at a chosen bitrate.
 *
 * Sites that publish adaptive streams keep the tracks in separate files, so a
 * download of the video alone would be silent. [MediaMuxer] is part of Android
 * itself, so this costs no APK size and, for tracks the chosen container takes
 * as they stand, no re-encoding: the compressed samples are copied across
 * untouched, which is fast and lossless.
 *
 * Two containers are written. An MP4 holds H.264 beside AAC — the pairing
 * every phone and every share target takes — and a soundtrack in any other
 * codec is converted by [AudioTranscoder] first, because the MP4 muxer will
 * not write it as it stands. A WebM holds VP9 beside Opus, which is what
 * YouTube publishes 1440p and 2160p as, and the only way to save those
 * resolutions without re-encoding the picture; both go in untouched.
 *
 * Not every device's muxer writes WebM, so [writesWebm] answers what this one
 * will take before such a resolution is ever offered. Nothing is inferred from
 * the Android version.
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
                    val container = call.argument<String>("container") ?: MP4
                    if (videoPath == null || audioPath == null || outputPath == null) {
                        result.error("bad_arguments", "video, audio and output are required", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        val outcome = runCatching {
                            mux(videoPath, audioPath, outputPath, container)
                        }
                        // A method result may only be delivered on the platform
                        // thread, and no activity need be on screen for that.
                        main.post { deliver(result, outcome) }
                    }
                }
                "transcode" -> {
                    val inputPath = call.argument<String>("input")
                    val outputPath = call.argument<String>("output")
                    val bitrate = call.argument<Int>("bitrate")
                    if (inputPath == null || outputPath == null || bitrate == null) {
                        result.error("bad_arguments", "input, output and bitrate are required", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        val outcome = runCatching {
                            AudioTranscoder.transcode(inputPath, outputPath, bitrate)
                        }
                        main.post { deliver(result, outcome) }
                    }
                }
                "capabilities" -> {
                    val probeDir = call.argument<String>("probeDir")
                    worker.execute {
                        val answer = mapOf(WEBM to (probeDir != null && writesWebm(probeDir)))
                        main.post { result.success(answer) }
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
     * Merges [videoPath] and [audioPath] into [outputPath] as [container],
     * converting the soundtrack first when that container will not take it as
     * it stands.
     *
     * Android's MP4 muxer accepts AAC and little else, while YouTube serves
     * most soundtracks as Opus. Copying the samples across is the fast,
     * lossless path and is taken whenever it can be: always for a WebM, whose
     * two codecs are the ones YouTube already published. Anything the MP4
     * muxer would refuse is re-encoded to AAC rather than dropped, which is
     * what keeps those videos from arriving silent.
     */
    private fun mux(videoPath: String, audioPath: String, outputPath: String, container: String) {
        if (container == WEBM) {
            combine(videoPath, audioPath, outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM)
            return
        }

        val mime = AudioTranscoder.audioMimeOf(audioPath)
            ?: error("No audio track in the downloaded file")

        if (mime.equals(AudioTranscoder.AAC_MIME, ignoreCase = true)) {
            combine(videoPath, audioPath, outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            return
        }

        val converted = File("$outputPath.aac")
        try {
            AudioTranscoder.transcode(audioPath, converted.path, AudioTranscoder.MERGE_BITRATE)
            combine(videoPath, converted.path, outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        } finally {
            converted.delete()
        }
    }

    /**
     * Copies the video track of [videoPath] and the first audio track of
     * [audioPath] into [outputPath] in [outputFormat].
     *
     * A partially written output is deleted on failure so a later retry never
     * publishes a truncated file.
     */
    private fun combine(
        videoPath: String,
        audioPath: String,
        outputPath: String,
        outputFormat: Int,
    ) {
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

            muxer = MediaMuxer(outputPath, outputFormat)
            val videoOut = addTrack(muxer, videoExtractor.getTrackFormat(videoTrack))
            val audioOut = addTrack(muxer, audioExtractor.getTrackFormat(audioTrack))
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

    /**
     * Whether this device's muxer writes a WebM holding VP9 beside Opus.
     *
     * Asked rather than inferred: WebM output has been part of [MediaMuxer]
     * since long before the oldest Android this app runs on, but which codecs
     * a given build's writer accepts is not something the version number
     * tells you. So one is written — headers, a sample on each track, and the
     * closing index — into a throwaway file under [probeDir]. Only a run that
     * completes counts, because a writer that takes the tracks and then
     * refuses to finish the file would fail after the whole download.
     */
    private fun writesWebm(probeDir: String): Boolean {
        val probe = File(probeDir, "webm-support.probe")
        return try {
            probe.parentFile?.mkdirs()
            val muxer = MediaMuxer(probe.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM)
            try {
                val video = muxer.addTrack(MediaFormat.createVideoFormat(VP9_MIME, 1280, 720))
                val audio = muxer.addTrack(opusFormat())
                muxer.start()
                writeProbeSample(muxer, video)
                writeProbeSample(muxer, audio)
                muxer.stop()
                true
            } finally {
                runCatching { muxer.release() }
            }
        } catch (error: Throwable) {
            false
        } finally {
            probe.delete()
        }
    }

    /**
     * An Opus track as the WebM writer wants one described: the `OpusHead`
     * identification header, the lead-in the decoder discards, and the run-up
     * a seek needs. The writer refuses a track without all three, so a probe
     * that left them out would be answering about a track nothing serves.
     */
    private fun opusFormat(): MediaFormat {
        val format = MediaFormat.createAudioFormat(OPUS_MIME, OPUS_RATE, 2)
        val head = ByteBuffer.allocate(19).order(ByteOrder.LITTLE_ENDIAN)
        head.put("OpusHead".toByteArray(Charsets.US_ASCII))
        head.put(1)                  // version
        head.put(2)                  // channel count
        head.putShort(OPUS_PRE_SKIP) // samples the decoder discards
        head.putInt(OPUS_RATE)       // rate of the original recording
        head.putShort(0)             // output gain
        head.put(0)                  // channel mapping family
        head.rewind()
        format.setByteBuffer("csd-0", head)
        format.setByteBuffer("csd-1", nanos(OPUS_PRE_SKIP * 1_000_000_000L / OPUS_RATE))
        format.setByteBuffer("csd-2", nanos(OPUS_SEEK_PRE_ROLL_NS))
        return format
    }

    private fun nanos(value: Long): ByteBuffer {
        val buffer = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putLong(value)
        buffer.rewind()
        return buffer
    }

    /** One byte on [track], flagged as a keyframe so the writer accepts it. */
    private fun writeProbeSample(muxer: MediaMuxer, track: Int) {
        val info = MediaCodec.BufferInfo()
        info.offset = 0
        info.size = 1
        info.presentationTimeUs = 0
        info.flags = MediaCodec.BUFFER_FLAG_KEY_FRAME
        muxer.writeSampleData(track, ByteBuffer.allocate(1), info)
    }

    /**
     * [format] added to [muxer], with the track named if it is refused.
     *
     * `addTrack` says only that it failed, and a merge has two tracks in it —
     * so without this the log cannot say which of them the writer would not
     * take, which is the one thing worth knowing when it happens.
     */
    private fun addTrack(muxer: MediaMuxer, format: MediaFormat): Int {
        return try {
            muxer.addTrack(format)
        } catch (error: Throwable) {
            val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
            error("Muxer refused $mime [$format]: ${error.message}")
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

        /** Container names, spelled the way Dart asks for them. */
        const val MP4 = "mp4"
        const val WEBM = "webm"

        const val VP9_MIME = "video/x-vnd.on2.vp9"
        const val OPUS_MIME = "audio/opus"

        /** The rate every Opus stream is coded at. */
        const val OPUS_RATE = 48_000

        /** Opus's own default lead-in, in samples. */
        const val OPUS_PRE_SKIP: Short = 312

        /** The 80 ms of audio a decoder needs before a seek is clean. */
        const val OPUS_SEEK_PRE_ROLL_NS = 80_000_000L

        /** 1 MB covers a keyframe of any resolution this app downloads. */
        const val MIN_BUFFER_BYTES = 1 shl 20
    }
}
