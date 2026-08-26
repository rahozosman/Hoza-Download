package com.hoza.download

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Publishes finished downloads into the user's shared Downloads collection.
 *
 * On Android 10 and newer this uses MediaStore, which lets the app write into
 * `Download/Hoza Download/` with **no storage permission at all** and makes the
 * files visible to file managers and media apps. On Android 9 and older there
 * is no MediaStore.Downloads, so the legacy public Downloads directory is used
 * and the result is handed to the media scanner.
 *
 * `MANAGE_EXTERNAL_STORAGE` is never requested: the app only ever touches files
 * it created itself.
 */
class MediaStoreChannel(
    private val context: Context,
    private val activityProvider: () -> Activity?,
) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "publish" -> result.success(publish(call))
                    "exists" -> result.success(exists(call))
                    "delete" -> result.success(delete(call))
                    "open" -> result.success(open(call))
                    "openLink" -> result.success(openLink(call))
                    "share" -> result.success(share(call))
                    "rename" -> result.success(rename(call))
                    "storageInfo" -> result.success(storageInfo())
                    "describeLocation" -> result.success(ROOT_FOLDER)
                    "isLegacy" -> result.success(isLegacy)
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                // Every failure reaches Dart as a typed error rather than an
                // exception that would crash the platform thread.
                result.error("storage_error", error.message, null)
            }
        }
    }

    /** Android 9 and older have no MediaStore.Downloads collection. */
    private val isLegacy: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    private fun relativePath(subFolder: String) = "$ROOT_FOLDER/$subFolder"

    /**
     * Moves [sourcePath] into shared storage.
     *
     * Returns the location Dart should store, plus the display name that was
     * actually used — Android may append a suffix when the name is taken.
     */
    private fun publish(call: MethodCall): Map<String, String> {
        val sourcePath = call.argument<String>("sourcePath")!!
        val fileName = call.argument<String>("fileName")!!
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        val subFolder = call.argument<String>("subFolder")!!

        val source = File(sourcePath)
        if (!source.exists()) throw IllegalStateException("Downloaded file is missing")

        return if (isLegacy) {
            publishLegacy(source, fileName, subFolder)
        } else {
            publishToMediaStore(source, fileName, mimeType, subFolder)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun publishToMediaStore(
        source: File,
        fileName: String,
        mimeType: String,
        subFolder: String,
    ): Map<String, String> {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, relativePath(subFolder))
            // Hidden from other apps until the bytes are fully written, so a
            // half-copied file is never offered to a media player.
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create the file in Downloads")

        try {
            resolver.openOutputStream(uri).use { output ->
                if (output == null) throw IllegalStateException("Downloads is not writable")
                source.inputStream().use { input -> input.copyTo(output, COPY_BUFFER) }
            }
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        source.delete()
        return mapOf(
            "location" to uri.toString(),
            "fileName" to (queryDisplayName(uri) ?: fileName),
        )
    }

    private fun publishLegacy(
        source: File,
        fileName: String,
        subFolder: String,
    ): Map<String, String> {
        val downloads = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        val target = File(downloads, "$APP_FOLDER/$subFolder")
        if (!target.exists() && !target.mkdirs()) {
            throw IllegalStateException("Could not create the Hoza Download folder")
        }

        val unique = uniqueLegacyFile(target, fileName)
        source.inputStream().use { input ->
            unique.outputStream().use { output -> input.copyTo(output, COPY_BUFFER) }
        }
        source.delete()

        // Without a scan the file stays invisible to gallery and file apps.
        MediaScannerConnection.scanFile(context, arrayOf(unique.absolutePath), null, null)

        return mapOf(
            "location" to unique.absolutePath,
            "fileName" to unique.name,
        )
    }

    /** `clip.mp4`, `clip (1).mp4`, … so an existing file is never overwritten. */
    private fun uniqueLegacyFile(directory: File, fileName: String): File {
        val candidate = File(directory, fileName)
        if (!candidate.exists()) return candidate

        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val suffix = if (dot > 0) fileName.substring(dot) else ""

        for (index in 1..MAX_NAME_ATTEMPTS) {
            val next = File(directory, "$stem ($index)$suffix")
            if (!next.exists()) return next
        }
        return File(directory, "$stem (${System.currentTimeMillis()})$suffix")
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun queryDisplayName(uri: Uri): String? {
        return context.contentResolver.query(
            uri,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    /** Whether a finished download already occupies this name. */
    private fun exists(call: MethodCall): Boolean {
        val fileName = call.argument<String>("fileName")!!
        val subFolder = call.argument<String>("subFolder")!!

        if (isLegacy) {
            val downloads = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS,
            )
            return File(downloads, "$APP_FOLDER/$subFolder/$fileName").exists()
        }
        return existsInMediaStore(fileName, subFolder)
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun existsInMediaStore(fileName: String, subFolder: String): Boolean {
        return context.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME} = ? AND " +
                "${MediaStore.Downloads.RELATIVE_PATH} LIKE ?",
            arrayOf(fileName, "${relativePath(subFolder)}%"),
            null,
        )?.use { it.moveToFirst() } ?: false
    }

    /** Removes a file this app published. Missing files count as removed. */
    private fun delete(call: MethodCall): Boolean {
        val location = call.argument<String>("location") ?: return false
        return if (location.startsWith("content://")) {
            context.contentResolver.delete(Uri.parse(location), null, null) > 0
        } else {
            val file = File(location)
            !file.exists() || file.delete()
        }
    }

    /** Hands the file to whichever app the user has for that media type. */
    private fun open(call: MethodCall): Boolean {
        val location = call.argument<String>("location") ?: return false
        val mimeType = call.argument<String>("mimeType") ?: "*/*"

        val uri = if (location.startsWith("content://")) {
            Uri.parse(location)
        } else {
            legacyContentUri(location) ?: return false
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            (activityProvider() ?: context).startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    /**
     * Opens the page a download came from in whatever handles it — the
     * platform's own app when it is installed (TikTok, Instagram, YouTube
     * all claim their links), otherwise the browser.
     */
    private fun openLink(call: MethodCall): Boolean {
        val raw = call.argument<String>("url") ?: return false
        val uri = Uri.parse(raw)
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return false

        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            (activityProvider() ?: context).startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    /** Looks up the scanned content URI for a legacy file path. */
    private fun legacyContentUri(path: String): Uri? = contentUriForPath(context, path)

    /** Hands the file to the Android share sheet. */
    private fun share(call: MethodCall): Boolean {
        val location = call.argument<String>("location") ?: return false
        val mimeType = call.argument<String>("mimeType") ?: "*/*"

        val uri = if (location.startsWith("content://")) {
            Uri.parse(location)
        } else {
            legacyContentUri(location) ?: return false
        }

        val send = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, null).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            (activityProvider() ?: context).startActivity(chooser)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    /**
     * Renames the saved file, not just the history entry.
     *
     * Returns the name the file ended up with, or null when the rename could
     * not be performed — the caller then leaves the record untouched rather
     * than showing a name that does not exist on disk.
     */
    private fun rename(call: MethodCall): String? {
        val location = call.argument<String>("location") ?: return null
        val newName = call.argument<String>("fileName") ?: return null
        if (newName.isBlank()) return null

        if (location.startsWith("content://")) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, newName)
            }
            val updated = context.contentResolver.update(
                Uri.parse(location),
                values,
                null,
                null,
            )
            return if (updated > 0) newName else null
        }

        val source = File(location)
        if (!source.exists()) return null
        val target = uniqueLegacyFile(source.parentFile ?: return null, newName)
        if (!source.renameTo(target)) return null

        // Both the old and new paths need rescanning so file apps stay correct.
        MediaScannerConnection.scanFile(
            context,
            arrayOf(source.absolutePath, target.absolutePath),
            null,
            null,
        )
        return target.name
    }

    /** Free and total bytes on the volume downloads are written to. */
    private fun storageInfo(): Map<String, Any> {
        val volume = context.getExternalFilesDir(null) ?: context.filesDir
        val stats = StatFs(volume.absolutePath)
        return mapOf(
            "free" to stats.availableBytes,
            "total" to stats.totalBytes,
        )
    }

    companion object {
        /**
         * Resolves a plain file path to the content URI the media scanner
         * created for it. Other apps cannot be handed a `file://` URI.
         */
        fun contentUriForPath(context: Context, path: String): Uri? {
            return context.contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                arrayOf(MediaStore.Files.FileColumns._ID),
                "${MediaStore.Files.FileColumns.DATA} = ?",
                arrayOf(path),
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                MediaStore.Files.getContentUri("external", cursor.getLong(0))
            }
        }

        private const val CHANNEL = "com.hoza.download/storage"
        private const val APP_FOLDER = "Hoza Download"
        private val ROOT_FOLDER = "${Environment.DIRECTORY_DOWNLOADS}/$APP_FOLDER"
        private const val COPY_BUFFER = 64 * 1024
        private const val MAX_NAME_ATTEMPTS = 999
    }
}
