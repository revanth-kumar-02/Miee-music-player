package com.example.miee.musicdrop

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * Manages persistent metadata for pending staged transfers across process death.
 * Never exposes raw sensitive system paths. Ensures orphan staging files are
 * deleted cleanly upon app recovery.
 */
class MusicDropRecoveryStore(private val context: Context) {

    companion object {
        private const val PREFS_NAME = "miee_music_drop_recovery"
        private const val KEY_PENDING_TRANSFERS = "pending_staged_transfers"
        private const val MAX_STAGING_AGE_MS = 24L * 60L * 60L * 1000L // 24 hours
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    data class StagedTransferRecord(
        val transferId: String,
        val stagingFileName: String, // Relative file name only (never full path)
        val title: String,
        val artist: String,
        val album: String?,
        val expectedSha256: String,
        val fileSize: Long,
        val timestamp: Long,
        val isVerified: Boolean
    ) {
        fun toJsonObject(): JSONObject {
            return JSONObject().apply {
                put("transferId", transferId)
                put("stagingFileName", stagingFileName)
                put("title", title)
                put("artist", artist)
                if (album != null) put("album", album)
                put("expectedSha256", expectedSha256)
                put("fileSize", fileSize)
                put("timestamp", timestamp)
                put("isVerified", isVerified)
            }
        }

        fun toMap(stagingDirectory: File): Map<String, Any?> {
            val file = File(stagingDirectory, stagingFileName)
            return mapOf(
                "transferId" to transferId,
                "title" to title,
                "artist" to artist,
                "album" to album,
                "expectedSha256" to expectedSha256,
                "fileSize" to fileSize,
                "stagingPath" to file.absolutePath,
                "timestamp" to timestamp,
                "isVerified" to isVerified
            )
        }

        companion object {
            fun fromJsonObject(json: JSONObject): StagedTransferRecord? {
                val transferId = json.optString("transferId")
                val stagingFileName = json.optString("stagingFileName")
                val title = json.optString("title")
                val artist = json.optString("artist")
                val sha = json.optString("expectedSha256")
                if (transferId.isBlank() || stagingFileName.isBlank() || title.isBlank()) {
                    return null
                }
                return StagedTransferRecord(
                    transferId = transferId,
                    stagingFileName = stagingFileName,
                    title = title,
                    artist = artist,
                    album = if (json.has("album")) json.optString("album") else null,
                    expectedSha256 = sha,
                    fileSize = json.optLong("fileSize", 0L),
                    timestamp = json.optLong("timestamp", System.currentTimeMillis()),
                    isVerified = json.optBoolean("isVerified", false)
                )
            }
        }
    }

    @Synchronized
    fun recordPendingStagedTransfer(record: StagedTransferRecord) {
        val list = loadAllRecords().toMutableList()
        list.removeAll { it.transferId == record.transferId }
        list.add(record)
        saveAllRecords(list)
    }

    @Synchronized
    fun removeStagedTransfer(transferId: String) {
        val list = loadAllRecords().toMutableList()
        list.removeAll { it.transferId == transferId }
        saveAllRecords(list)
    }

    @Synchronized
    fun getPendingTransfers(): List<StagedTransferRecord> {
        return loadAllRecords()
    }

    /**
     * Inspects the staging directory, deletes orphaned and corrupt files,
     * verifies checksums of recorded files, and returns verified records.
     */
    @Synchronized
    fun recoverAndCleanup(stagingDir: File): List<StagedTransferRecord> {
        if (!stagingDir.exists()) {
            stagingDir.mkdirs()
            saveAllRecords(emptyList())
            return emptyList()
        }

        val now = System.currentTimeMillis()
        val allRecords = loadAllRecords().toMutableList()
        val recordMap = allRecords.associateBy { it.stagingFileName }.toMutableMap()
        val verifiedRecords = mutableListOf<StagedTransferRecord>()

        // 1. Inspect existing physical files in stagingDir
        val files = stagingDir.listFiles() ?: emptyArray()
        val foundFileNames = mutableSetOf<String>()

        for (file in files) {
            foundFileNames.add(file.name)
            val record = recordMap[file.name]

            val isStale = (now - file.lastModified()) > MAX_STAGING_AGE_MS
            if (record == null || isStale) {
                // Orphaned or stale temporary staging file -> delete
                try {
                    file.delete()
                } catch (_: Exception) {}
                continue
            }

            // Verify file size and checksum
            if (file.length() <= 0L || file.length() != record.fileSize) {
                try {
                    file.delete()
                } catch (_: Exception) {}
                recordMap.remove(file.name)
                continue
            }

            // Checksum verification
            val actualSha256 = calculateSha256(file)
            if (record.expectedSha256.isNotBlank() && !actualSha256.equals(record.expectedSha256, ignoreCase = true)) {
                try {
                    file.delete()
                } catch (_: Exception) {}
                recordMap.remove(file.name)
                continue
            }

            // Valid and verified
            verifiedRecords.add(record)
        }

        // 2. Remove records whose files were not found on disk
        saveAllRecords(verifiedRecords)
        return verifiedRecords
    }

    private fun loadAllRecords(): List<StagedTransferRecord> {
        val jsonStr = prefs.getString(KEY_PENDING_TRANSFERS, null) ?: return emptyList()
        return try {
            val array = JSONArray(jsonStr)
            val list = mutableListOf<StagedTransferRecord>()
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                StagedTransferRecord.fromJsonObject(obj)?.let { list.add(it) }
            }
            list
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveAllRecords(records: List<StagedTransferRecord>) {
        val array = JSONArray()
        for (r in records) {
            array.put(r.toJsonObject())
        }
        prefs.edit().putString(KEY_PENDING_TRANSFERS, array.toString()).apply()
    }

    private fun calculateSha256(file: File): String {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(16384)
            var bytesRead: Int
            val input = FileInputStream(file)
            try {
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    digest.update(buffer, 0, bytesRead)
                }
            } finally {
                try { input.close() } catch (_: Exception) {}
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            ""
        }
    }
}
