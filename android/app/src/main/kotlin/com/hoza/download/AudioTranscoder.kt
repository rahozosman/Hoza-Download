package com.hoza.download

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Re-encodes an audio file as AAC at a chosen bitrate, into an MP4 container.
 *
 * Two things need this. YouTube publishes most soundtracks as Opus, which
 * Android's muxer will not write into an MP4 — so an Opus track has to become
 * AAC before it can be merged into a video, and without that step those videos
 * arrive silent or not at all. And an audio download at a bitrate YouTube does
 * not serve can only be produced by encoding one.
 *
 * Re-encoding is never a quality gain: writing a 128 kbps track out at
 * 320 kbps makes a larger file of the same sound. It is done because the
 * container and the bitrate are what was asked for.
 *
 * Everything here is Android's own MediaCodec, so the app still carries no
 * media library and nothing is added to the APK.
 */
internal object AudioTranscoder {

    /** AAC-LC in an MP4 container: what Android's muxer takes on every phone. */
    const val AAC_MIME = "audio/mp4a-latm"

    /**
     * Bitrate a soundtrack is re-encoded at on its way into a video.
     *
     * Comfortably above the ~160 kbps Opus YouTube serves, so the single
     * re-encode the merge costs is not something a listener can pick out.
     */
    const val MERGE_BITRATE = 192_000

    /** Rewrites [inputPath] as AAC at [bitrate] bits per second in [outputPath]. */
    fun transcode(inputPath: String, outputPath: String, bitrate: Int) {
        Session(inputPath, outputPath, bitrate).run()
    }

    /** MIME type of the first audio track of [path], or null when it has none. */
    fun audioMimeOf(path: String): String? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(path)
            (0 until extractor.trackCount)
                .map { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME).orEmpty() }
                .firstOrNull { it.startsWith("audio/") }
        } finally {
            runCatching { extractor.release() }
        }
    }

    /**
     * One decode-and-encode run.
     *
     * The decoder is started first and the encoder only once the decoder has
     * announced what it actually produces: an Opus or HE-AAC track can decode
     * to a different sample rate or channel count than its header declares,
     * and an encoder configured from that header would write a file that plays
     * at the wrong speed.
     */
    private class Session(
        private val inputPath: String,
        private val outputPath: String,
        private val bitrate: Int,
    ) {
        private val extractor = MediaExtractor()

        /** Decoded PCM waiting for an encoder input buffer to become free. */
        private val pcm = ArrayDeque<ByteBuffer>()

        private val decoderInfo = MediaCodec.BufferInfo()
        private val encoderInfo = MediaCodec.BufferInfo()

        private var decoder: MediaCodec? = null
        private var encoder: MediaCodec? = null
        private var muxer: MediaMuxer? = null

        private var sampleRate = 0
        private var channels = 0

        /**
         * PCM frames handed to the encoder so far. Timestamps are counted from
         * this rather than copied from the source, so a gap or an overlap in
         * the source cannot drift the output out of sync.
         */
        private var framesQueued = 0L

        private var muxerTrack = -1
        private var muxing = false

        private var extractorDone = false
        private var decoderDone = false
        private var encoderInputDone = false
        private var encoderDone = false

        fun run() {
            try {
                open()
                while (!encoderDone) {
                    // The decoder always announces its output format before its
                    // first sample; reaching the end without one means nothing
                    // was decoded, and the loop must not wait on an encoder
                    // that will never exist.
                    if (decoderDone && encoder == null) {
                        error("This device could not decode the downloaded audio")
                    }
                    feedDecoder()
                    drainDecoder()
                    feedEncoder()
                    drainEncoder()
                }
                if (!muxing) error("The re-encoded audio produced no samples")
                muxer?.stop()
            } catch (error: Throwable) {
                File(outputPath).delete()
                throw error
            } finally {
                release()
            }
        }

        private fun open() {
            extractor.setDataSource(inputPath)
            val track = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    .orEmpty().startsWith("audio/")
            } ?: error("No audio track in the downloaded file")

            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)
                ?: error("The downloaded audio names no format")

            decoder = MediaCodec.createDecoderByType(mime).apply {
                configure(format, null, null, 0)
                start()
            }
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        }

        private fun feedDecoder() {
            if (extractorDone) return
            val codec = decoder ?: return
            val index = codec.dequeueInputBuffer(TIMEOUT_US)
            if (index < 0) return
            val buffer = codec.getInputBuffer(index) ?: return

            val read = extractor.readSampleData(buffer, 0)
            if (read < 0) {
                codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                extractorDone = true
            } else {
                codec.queueInputBuffer(index, 0, read, extractor.sampleTime, 0)
                extractor.advance()
            }
        }

        private fun drainDecoder() {
            if (decoderDone) return
            val codec = decoder ?: return
            val index = codec.dequeueOutputBuffer(decoderInfo, TIMEOUT_US)

            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                startEncoder(codec.outputFormat)
                return
            }
            if (index < 0) return

            if (decoderInfo.size > 0) {
                val buffer = codec.getOutputBuffer(index)
                if (buffer != null) {
                    buffer.position(decoderInfo.offset)
                    buffer.limit(decoderInfo.offset + decoderInfo.size)
                    // Copied out: the codec takes its buffer back the moment it
                    // is released, and this PCM may wait for the encoder to
                    // have room for it.
                    val copy = ByteBuffer.allocate(decoderInfo.size)
                    copy.put(buffer)
                    copy.flip()
                    pcm.addLast(copy)
                }
            }
            codec.releaseOutputBuffer(index, false)
            if (decoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                decoderDone = true
            }
        }

        private fun startEncoder(decoded: MediaFormat) {
            if (encoder != null) return
            sampleRate = decoded.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            channels = decoded.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            encoder = createEncoder()
        }

        /**
         * The encoder, at the highest bitrate of [ladder] it will accept.
         *
         * Devices disagree about how high their AAC encoder goes, and one that
         * refuses 320 kbps refuses it at `configure` time. Stepping down beats
         * failing the download: a 256 kbps file is what that phone can make,
         * and it is still the file the user asked to save.
         */
        private fun createEncoder(): MediaCodec {
            var failure: Throwable? = null
            for (rate in ladder()) {
                val codec = MediaCodec.createEncoderByType(AAC_MIME)
                try {
                    codec.configure(
                        formatFor(rate),
                        null,
                        null,
                        MediaCodec.CONFIGURE_FLAG_ENCODE,
                    )
                    codec.start()
                    return codec
                } catch (error: Throwable) {
                    failure = error
                    runCatching { codec.release() }
                }
            }
            throw failure ?: IllegalStateException("No AAC encoder on this device")
        }

        private fun formatFor(rate: Int) =
            MediaFormat.createAudioFormat(AAC_MIME, sampleRate, channels).apply {
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, rate)
            }

        /** The wanted bitrate, then the fallbacks below it. */
        private fun ladder(): List<Int> {
            val wanted = supported(bitrate)
            val steps = listOf(wanted, 256_000, 192_000, 128_000)
                .filter { it <= wanted }
                .distinct()
            return steps.ifEmpty { listOf(wanted) }
        }

        /** [wanted], clamped to what this device's AAC encoder advertises. */
        private fun supported(wanted: Int): Int {
            for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
                if (!info.isEncoder) continue
                if (info.supportedTypes.none { it.equals(AAC_MIME, ignoreCase = true) }) continue
                val range = runCatching {
                    info.getCapabilitiesForType(AAC_MIME).audioCapabilities?.bitrateRange
                }.getOrNull() ?: continue
                return wanted.coerceIn(range.lower, range.upper)
            }
            return wanted
        }

        private fun feedEncoder() {
            if (encoderInputDone) return
            val codec = encoder ?: return
            // Nothing to send yet and more is coming: leave the input buffer
            // for a round that has PCM to put in it.
            if (pcm.isEmpty() && !decoderDone) return

            val index = codec.dequeueInputBuffer(TIMEOUT_US)
            if (index < 0) return
            val buffer = codec.getInputBuffer(index) ?: return
            buffer.clear()

            var written = 0
            while (pcm.isNotEmpty() && buffer.hasRemaining()) {
                val head = pcm.first()
                val take = minOf(head.remaining(), buffer.remaining())
                val slice = head.duplicate()
                slice.limit(slice.position() + take)
                buffer.put(slice)
                head.position(head.position() + take)
                written += take
                if (!head.hasRemaining()) pcm.removeFirst()
            }

            val presentationTimeUs = framesQueued * 1_000_000L / sampleRate
            if (written == 0) {
                codec.queueInputBuffer(
                    index,
                    0,
                    0,
                    presentationTimeUs,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                )
                encoderInputDone = true
            } else {
                codec.queueInputBuffer(index, 0, written, presentationTimeUs, 0)
                framesQueued += written / (channels * BYTES_PER_SAMPLE)
            }
        }

        private fun drainEncoder() {
            val codec = encoder ?: return
            val index = codec.dequeueOutputBuffer(encoderInfo, TIMEOUT_US)

            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val target = muxer ?: return
                muxerTrack = target.addTrack(codec.outputFormat)
                target.start()
                muxing = true
                return
            }
            if (index < 0) return

            // The codec-config buffer is the encoder describing itself; the
            // muxer already took that from the output format.
            if (encoderInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                encoderInfo.size = 0
            }
            if (encoderInfo.size > 0 && muxing) {
                val buffer = codec.getOutputBuffer(index)
                if (buffer != null) {
                    buffer.position(encoderInfo.offset)
                    buffer.limit(encoderInfo.offset + encoderInfo.size)
                    muxer?.writeSampleData(muxerTrack, buffer, encoderInfo)
                }
            }
            codec.releaseOutputBuffer(index, false)
            if (encoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                encoderDone = true
            }
        }

        private fun release() {
            runCatching { muxer?.release() }
            runCatching { decoder?.stop() }
            runCatching { decoder?.release() }
            runCatching { encoder?.stop() }
            runCatching { encoder?.release() }
            runCatching { extractor.release() }
        }
    }

    /**
     * How long a codec call may block. Short enough that no single step stalls
     * the run, long enough that the loop is not a busy wait.
     */
    private const val TIMEOUT_US = 10_000L

    /** Android's audio decoders hand back 16-bit PCM. */
    private const val BYTES_PER_SAMPLE = 2
}
