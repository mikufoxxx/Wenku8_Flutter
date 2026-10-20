package org.mewx.wenku8_flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.os.Build
import android.provider.Settings
import android.Manifest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.util.concurrent.Executors

/** SAF for chosen folders; explicit system permission for optional shared-storage
 * scanning. Account credentials and private application files stay separate. */
class BookDocuments(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val io = Executors.newSingleThreadExecutor()
    private val preferences = activity.getSharedPreferences("book_documents", 0)
    private data class Pending(val method: String, val result: MethodChannel.Result)
    private var pending: Pending? = null
    private var closed = false
    private val root = File(activity.cacheDir, "book-documents").apply { mkdirs() }
    private val scanner = BookFolderScanner(activity)
    companion object { private const val REQUEST = 8020; private const val ALL_REQUEST = 8021; private const val MAX_SYNC = 256L * 1024 * 1024 }

    private fun name(uri: Uri, fallback: String = "wenku8.wenku8sync"): String = activity.contentResolver.query(uri,
        arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
        if (it.moveToFirst()) it.getString(0) else null
    } ?: fallback

    private fun selected(): Uri = preferences.getString("sync_uri", null)?.let(Uri::parse)
        ?: throw IllegalStateException("请先选择云同步文件")

    private fun canWrite(uri: Uri): Boolean = activity.contentResolver.query(uri,
        arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null)?.use {
        it.moveToFirst() && (it.getInt(0) and DocumentsContract.Document.FLAG_SUPPORTS_WRITE) != 0
    } ?: false

    private fun copy(uri: Uri, target: File, max: Long) {
        val partial = File(target.path + ".part")
        try {
            activity.contentResolver.openInputStream(uri)?.use { input ->
                partial.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024); var size = 0L
                    while (true) {
                        val count = input.read(buffer); if (count < 0) break
                        size += count; require(size <= max) { "文件超过 ${max / (1024 * 1024)} MiB 大小限制" }
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            } ?: error("无法读取所选文件")
            check(partial.renameTo(target)) { "保存临时文件失败" }
        } finally { partial.delete() }
    }

    private fun file(path: String): File {
        val candidate = File(path).canonicalFile
        require(candidate.parentFile == root.canonicalFile && candidate.isFile) { "文件路径无效" }
        return candidate
    }

    // Network downloads live in a different private cache subtree. Permit it
    // for decoding only; sync writes retain their original strict root check.
    private fun bookTextFile(path: String): File {
        val candidate = File(path).canonicalFile
        val cloud = File(activity.cacheDir, "cloud-book-import").canonicalFile
        require(candidate.isFile && (candidate.parentFile == root.canonicalFile ||
            candidate.path.startsWith(cloud.path + File.separator))) { "文件路径无效" }
        return candidate
    }

    private fun equal(a: File, b: File): Boolean {
        if (a.length() != b.length()) return false
        a.inputStream().use { left -> b.inputStream().use { right ->
            val x = ByteArray(65536); val y = ByteArray(65536)
            while (true) {
                val n = left.read(x); if (n < 0) return right.read() < 0
                var offset = 0
                while (offset < n) { val read = right.read(y, offset, n - offset); if (read < 0) return false; offset += read }
                for (i in 0 until n) if (x[i] != y[i]) return false
            }
        } }
    }

    private fun background(result: MethodChannel.Result, action: () -> Any?) {
        if (closed) { result.error("closed", "文件页面已关闭，请返回文库后重试", null); return }
        io.execute {
            try { val value = action(); activity.runOnUiThread {
                if (closed) result.error("closed", "文件页面已关闭，请返回文库后重试", null) else result.success(value)
            } }
            catch (error: Exception) { activity.runOnUiThread { result.error("document", error.message ?: "文件操作失败，请重试", null) } }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "selectAllScan" -> {
                if (pending != null) { result.error("busy", "请先完成当前文件选择", null); return }
                if (scanner.canReadAll()) { background(result) { scanner.selectAll() }; return }
                pending = Pending(call.method, result)
                try {
                    if (Build.VERSION.SDK_INT >= 30) {
                        val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:${activity.packageName}"))
                        @Suppress("DEPRECATION") activity.startActivityForResult(intent, ALL_REQUEST)
                    } else activity.requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), ALL_REQUEST)
                } catch (_: Exception) { pending = null; result.error("permission", "系统未提供共享存储授权，请选择指定文件夹", null) }
            }
            "pickBook", "pickBooks", "pickFont", "pickBackgroundImage", "openSync", "createSync", "selectScanFolder" -> {
                if (pending != null) { result.error("busy", "请先完成当前文件选择", null); return }
                val create = call.method == "createSync"
                val folder = call.method == "selectScanFolder"
                val choosingBooks = call.method == "pickBook" || call.method == "pickBooks"
                val intent = Intent(if (folder) Intent.ACTION_OPEN_DOCUMENT_TREE else if (create) Intent.ACTION_CREATE_DOCUMENT else if (choosingBooks) Intent.ACTION_GET_CONTENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                    if (!folder) { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*" }
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    if (!folder && call.method != "pickFont" && call.method != "pickBackgroundImage") addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    if (call.method == "pickBackgroundImage") {
                        type = "image/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/webp"))
                    }
                    if (create) { type = "application/octet-stream"; putExtra(Intent.EXTRA_TITLE, "文库同步.wenku8sync") }
                    if (call.method == "pickBook" || call.method == "pickBooks") {
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/*", "application/epub+zip", "application/zip", "application/x-zip-compressed", "application/x-mobipocket-ebook", "application/vnd.amazon.ebook", "application/pdf", "application/rtf", "application/xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/octet-stream"))
                        if (call.method == "pickBooks") putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                }
                pending = Pending(call.method, result)
                try { @Suppress("DEPRECATION") activity.startActivityForResult(
                    if (folder || choosingBooks) Intent.createChooser(intent, if (folder) "选择支持文件夹授权的应用" else "选择文件应用") else intent,
                    REQUEST) }
                catch (_: Exception) { pending = null; result.error("picker", "系统文件选择器不可用", null) }
            }
            "scanFolderInfo" -> background(result) { scanner.info() }
            "setScanAutomatic" -> background(result) { scanner.setAutomatic(call.argument<Boolean>("value") == true); null }
            "disconnectScanFolder" -> background(result) { scanner.disconnect(); null }
            "scanBooks" -> background(result) { scanner.scan() }
            "scanFormats" -> background(result) { scanner.formats().toList() }
            "setScanFormats" -> background(result) { scanner.setFormats(call.argument<List<String>>("extensions") ?: emptyList()); null }
            "stageScanBook" -> background(result) { scanner.stage(call.argument<String>("token") ?: "", root, ::copy) }
            "markScanBook" -> background(result) { scanner.markImported(call.argument<String>("token") ?: ""); null }
            "finishBookScan" -> background(result) { scanner.finish(); null }
            "syncInfo" -> background(result) {
                val value = preferences.getString("sync_uri", null)
                if (value == null) null else mapOf("name" to name(Uri.parse(value)), "authority" to (Uri.parse(value).authority ?: ""), "created" to preferences.getBoolean("sync_new", false))
            }
            "releaseBooks" -> background(result) {
                for (path in (call.argument<List<String>>("paths") ?: emptyList()).distinct()) {
                    val source = File(path).canonicalFile
                    require(source.parentFile == root.canonicalFile && source.name.startsWith("import-") && source.name.endsWith(".source")) { "文件路径无效" }
                    check(!source.exists() || source.isFile && source.delete()) { "清理临时文件失败" }
                }
                null
            }
            "prepareBook" -> background(result) {
                val source = bookTextFile(call.argument<String>("path") ?: "")
                BookArchiveImport(root).apply { documents = BookMarkupImport(root, BookPdfImport(activity, root)::read) }
                    .prepare(call.argument<String>("name") ?: "", source)
            }
            "readSync" -> background(result) {
                val snapshot = File(root, "cloud-before.wenku8sync")
                copy(selected(), snapshot, MAX_SYNC)
                mapOf("path" to snapshot.path, "size" to snapshot.length(), "outputPath" to File(root, "cloud-next.wenku8sync").path)
            }
            "writeSync" -> background(result) {
                val target = selected()
                require(canWrite(target)) { "所选云文档不支持写入，请换一个文件" }
                val next = file(call.argument<String>("path") ?: "")
                val before = file(call.argument<String>("expectedPath") ?: "")
                require(next.length() in 1..MAX_SYNC) { "同步文件过大" }
                val fresh = File(root, "cloud-check.wenku8sync")
                copy(target, fresh, MAX_SYNC)
                check(equal(before, fresh)) { "云端文件已发生变化，请重新同步" }
                // Retain both recoverable snapshots before a provider write.
                val recovery = File(activity.filesDir, "sync-recovery").apply { mkdirs() }
                before.copyTo(File(recovery, "cloud-before.wenku8sync"), overwrite = true)
                next.copyTo(File(recovery, "cloud-next.wenku8sync"), overwrite = true)
                activity.contentResolver.openFileDescriptor(target, "rwt")?.use { fd ->
                    java.io.FileOutputStream(fd.fileDescriptor).use { output ->
                        next.inputStream().use { it.copyTo(output) }; output.flush()
                    }
                } ?: error("无法写入云端文件，恢复副本已保留")
                val after = File(root, "cloud-after.wenku8sync")
                copy(target, after, MAX_SYNC)
                check(equal(next, after)) { "云端写入未完整确认，恢复副本已保留" }
                check(preferences.edit().putBoolean("sync_new", false).commit())
                true
            }
            "disconnectSync" -> background(result) {
                preferences.getString("sync_uri", null)?.let { value ->
                    try { activity.contentResolver.releasePersistableUriPermission(Uri.parse(value),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) } catch (_: Exception) { }
                }
                check(preferences.edit().remove("sync_uri").remove("sync_new").commit()); null
            }
            "recoverSync" -> background(result) {
                val which = call.argument<String>("which")
                require(which in setOf("before", "next"))
                val recovery = File(activity.filesDir, "sync-recovery/cloud-$which.wenku8sync")
                if (!recovery.isFile) null else {
                    val copy = File(root, "recovery.wenku8sync"); recovery.copyTo(copy, overwrite = true); copy.path
                }
            }
            "decodeText" -> background(result) {
                val source = bookTextFile(call.argument<String>("path") ?: "")
                require(source.length() <= 40L * 1024 * 1024) { "单本 TXT 不能超过 40 MiB" }
                val bytes = source.readBytes()
                val requested = call.argument<String>("encoding") ?: "auto"
                val charset = if (requested != "auto") Charset.forName(requested) else when {
                    bytes.size >= 2 && bytes[0] == 0xff.toByte() && bytes[1] == 0xfe.toByte() -> Charsets.UTF_16LE
                    bytes.size >= 2 && bytes[0] == 0xfe.toByte() && bytes[1] == 0xff.toByte() -> Charsets.UTF_16BE
                    else -> try { Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)); Charsets.UTF_8 }
                        catch (_: Exception) { Charset.forName("GB18030") }
                }
                charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString().removePrefix("\uFEFF")
            }
            "decodeTextFile" -> background(result) {
                val source = bookTextFile(call.argument<String>("path") ?: "")
                val target = File.createTempFile("import-", ".source", root)
                try { BookTextDecoder.normalize(source, target, call.argument<String>("encoding") ?: "auto") }
                catch (_: java.nio.charset.CharacterCodingException) { error("文本编码无法识别，请在书库设置选择正确的 TXT 编码后重试") }
                target.path
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request == ALL_REQUEST) { finishAllPermission(); return true }
        if (request != REQUEST) return false
        val operation = pending ?: return true
        pending = null
        if (code != Activity.RESULT_OK || data == null) { operation.result.success(null); return true }
        val uris = linkedSetOf<Uri>()
        if (operation.method == "pickBooks") data.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) uris.add(clip.getItemAt(index).uri)
        }
        data.data?.let(uris::add)
        if (uris.isEmpty()) { operation.result.success(null); return true }
        val uri = uris.first()
        background(operation.result) {
            if (operation.method == "selectScanFolder") {
                scanner.select(uri, data.flags)
            } else if (operation.method == "pickBackgroundImage") {
                val target = File.createTempFile("import-", ".source", root)
                try { copy(uri, target, 32L * 1024 * 1024) }
                catch (error: Exception) { target.delete(); throw error }
                mapOf("name" to name(uri, "背景图片"), "path" to target.path)
            } else if (operation.method == "pickFont") {
                val display = name(uri)
                require(display.substringAfterLast('.').lowercase() in setOf("ttf", "otf")) { "请选择 TTF 或 OTF 字体" }
                val target = File.createTempFile("import-", ".source", root)
                try { copy(uri, target, 32L * 1024 * 1024) }
                catch (error: Exception) { target.delete(); throw error }
                mapOf("name" to display, "path" to target.path)
            } else if (operation.method == "pickBooks") {
                uris.map { selected ->
                    var display = "所选文件"
                    var target: File? = null
                    try {
                        display = name(selected)
                        require(BookArchiveImport.supported(display)) { "请选择支持的电子书或文档" }
                        val destination = File.createTempFile("import-", ".source", root)
                        target = destination
                        copy(selected, destination, BookArchiveImport.limit(display))
                        mapOf("name" to display, "path" to destination.path)
                    } catch (error: Exception) {
                        target?.delete()
                        mapOf("name" to display, "error" to (error.message ?: "无法读取所选文件"))
                    }
                }
            } else if (operation.method == "pickBook") {
                val display = name(uri)
                require(BookArchiveImport.supported(display)) { "请选择支持的电子书或文档" }
                val target = File(root, "import-source")
                copy(uri, target, BookArchiveImport.limit(display))
                mapOf("name" to display, "path" to target.path)
            } else {
                require(canWrite(uri)) { "此云文档不支持写入，请选择可编辑的同步文件" }
                val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                require(flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0 && flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0) { "云端未授予读写权限，请重新选择" }
                activity.contentResolver.takePersistableUriPermission(uri, flags)
                check(preferences.edit().putString("sync_uri", uri.toString()).putBoolean("sync_new", operation.method == "createSync").commit())
                mapOf("name" to name(uri), "authority" to (uri.authority ?: ""), "created" to (operation.method == "createSync"))
            }
        }
        return true
    }
    fun onRequestPermissionsResult(request: Int): Boolean {
        if (request != ALL_REQUEST) return false
        finishAllPermission()
        return true
    }
    private fun finishAllPermission() {
        val operation = pending?.takeIf { it.method == "selectAllScan" } ?: return
        pending = null
        if (scanner.canReadAll()) background(operation.result) { scanner.selectAll() }
        else operation.result.success(null)
    }
    fun close() {
        closed = true; pending?.result?.error("closed", "页面已关闭，请重试", null); pending = null
        io.execute { try { scanner.finish() } catch (_: Exception) { /* The next scan safely retries unacknowledged files. */ } }
        io.shutdown()
    }
}
