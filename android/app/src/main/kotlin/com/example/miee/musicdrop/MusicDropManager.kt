package com.example.miee.musicdrop

import android.Manifest
import android.app.Activity
import android.app.Application
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.nfc.NfcAdapter
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Isolated native bridge for Google Nearby Connections in Miee Music Drop.
 * Handles platform compatibility, runtime permissions, discovery, advertising,
 * connection negotiation, secure payload transfer & verification,
 * and Phase 4 reliable background receiving with user consent and recovery.
 */
class MusicDropManager(context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val CHANNEL_METHODS = "com.example.miee/music_drop"
        const val CHANNEL_EVENTS = "com.example.miee/music_drop_events"
        const val SERVICE_ID = "com.example.miee.music_drop"
        const val PERMISSION_REQUEST_CODE = 4129

        const val MAX_METADATA_BYTES = 64 * 1024 // 64 KB
        const val MAX_AUDIO_FILE_BYTES = 150L * 1024L * 1024L // 150 MB
        val SUPPORTED_AUDIO_EXTENSIONS = setOf("mp3", "m4a", "aac", "flac", "wav", "ogg", "opus")

        @Volatile
        private var instance: MusicDropManager? = null

        fun getInstance(context: Context): MusicDropManager {
            return instance ?: synchronized(this) {
                instance ?: MusicDropManager(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    private val appContext: Context = context.applicationContext
    private var currentActivity: Activity? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool()
    private var eventSink: EventChannel.EventSink? = null
    private val connectionsClient = Nearby.getConnectionsClient(appContext)

    private val notificationHelper = MusicDropNotificationHelper.getInstance(appContext)
    private val recoveryStore = MusicDropRecoveryStore(appContext)

    private var isAdvertising = false
    private var isDiscovering = false
    private var isBackgroundServiceActive = false
    private var isAppInForeground = true
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var localEndpointName: String = "Miee (${Build.MODEL})"

    // Payload & Transfer Tracking
    private val incomingFilePayloads = ConcurrentHashMap<Long, Payload>()
    private val filePayloadIdToTransferId = ConcurrentHashMap<Long, String>()
    private val transferIdToFilePayloadId = ConcurrentHashMap<String, Long>()
    private val transferIdToExpectedSha256 = ConcurrentHashMap<String, String>()
    private val transferIdToSanitizedName = ConcurrentHashMap<String, String>()
    private val transferIdToMetadata = ConcurrentHashMap<String, Map<String, String>>()
    private val stagingFiles = ConcurrentHashMap<String, File>() // transferId -> Staged File

    // Progress throttling for background notifications
    private val lastProgressNotificationTime = ConcurrentHashMap<String, Long>()

    init {
        val app = appContext as? Application
        app?.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            private var resumedActivities = 0

            override fun onActivityResumed(activity: Activity) {
                currentActivity = activity
                resumedActivities++
                isAppInForeground = resumedActivities > 0
            }

            override fun onActivityPaused(activity: Activity) {
                resumedActivities--
                isAppInForeground = resumedActivities > 0
                if (currentActivity == activity) {
                    currentActivity = null
                }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                currentActivity = activity
            }
            override fun onActivityStarted(activity: Activity) {
                currentActivity = activity
            }
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {
                if (currentActivity == activity) {
                    currentActivity = null
                }
            }
        })

        // Clean up orphaned staging files on initialization
        executor.execute {
            val stagingDir = File(appContext.cacheDir, "music_drop_staging")
            val recovered = recoveryStore.recoverAndCleanup(stagingDir)
            for (rec in recovered) {
                val file = File(stagingDir, rec.stagingFileName)
                if (file.exists()) {
                    stagingFiles[rec.transferId] = file
                    transferIdToSanitizedName[rec.transferId] = rec.stagingFileName
                    transferIdToExpectedSha256[rec.transferId] = rec.expectedSha256
                }
            }
        }
    }

    fun attachActivity(activity: Activity) {
        this.currentActivity = activity
        this.isAppInForeground = true
    }

    fun detachActivity(activity: Activity) {
        if (this.currentActivity == activity) {
            this.currentActivity = null
            this.isAppInForeground = false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> handleIsSupported(result)
            "checkPermissions" -> handleCheckPermissions(result)
            "requestPermissions" -> handleRequestPermissions(result)
            "startAdvertising" -> {
                val customName = call.argument<String>("customName")
                handleStartAdvertising(customName, result)
            }
            "stopAdvertising" -> handleStopAdvertising(result)
            "startDiscovery" -> handleStartDiscovery(result)
            "stopDiscovery" -> handleStopDiscovery(result)
            "connect" -> {
                val endpointId = call.argument<String>("endpointId")
                if (endpointId != null) {
                    handleConnect(endpointId, result)
                } else {
                    result.error("INVALID_ARGUMENT", "endpointId is required", null)
                }
            }
            "acceptConnection" -> {
                val endpointId = call.argument<String>("endpointId")
                if (endpointId != null) {
                    handleAcceptConnection(endpointId, result)
                } else {
                    result.error("INVALID_ARGUMENT", "endpointId is required", null)
                }
            }
            "rejectConnection" -> {
                val endpointId = call.argument<String>("endpointId")
                if (endpointId != null) {
                    handleRejectConnection(endpointId, result)
                } else {
                    result.error("INVALID_ARGUMENT", "endpointId is required", null)
                }
            }
            "disconnect" -> {
                val endpointId = call.argument<String>("endpointId")
                if (endpointId != null) {
                    handleDisconnect(endpointId, result)
                } else {
                    result.error("INVALID_ARGUMENT", "endpointId is required", null)
                }
            }
            "stopAll" -> handleStopAll(result)

            // Phase 2: Payload Transfer Engine methods
            "sendMetadata" -> {
                val endpointId = call.argument<String>("endpointId")
                val metadataJson = call.argument<String>("metadataJson")
                if (endpointId != null && metadataJson != null) {
                    handleSendMetadata(endpointId, metadataJson, result)
                } else {
                    result.error("INVALID_ARGUMENT", "endpointId and metadataJson are required", null)
                }
            }
            "sendAudioFile" -> {
                val endpointId = call.argument<String>("endpointId")
                val filePath = call.argument<String>("filePath")
                val metadataJson = call.argument<String>("metadataJson")
                if (endpointId != null && filePath != null && metadataJson != null) {
                    handleSendAudioFile(endpointId, filePath, metadataJson, result)
                } else {
                    result.error("INVALID_ARGUMENT", "endpointId, filePath and metadataJson are required", null)
                }
            }
            "cancelPayload" -> {
                val payloadId = call.argument<Number>("payloadId")?.toLong()
                if (payloadId != null) {
                    handleCancelPayload(payloadId, result)
                } else {
                    result.error("INVALID_ARGUMENT", "payloadId is required", null)
                }
            }
            "commitReceivedFile" -> {
                val transferId = call.argument<String>("transferId")
                val destinationDir = call.argument<String>("destinationDir")
                val customName = call.argument<String>("customName")
                if (transferId != null) {
                    handleCommitReceivedFile(transferId, destinationDir, customName, result)
                } else {
                    result.error("INVALID_ARGUMENT", "transferId is required", null)
                }
            }
            "discardReceivedFile" -> {
                val transferId = call.argument<String>("transferId")
                if (transferId != null) {
                    handleDiscardReceivedFile(transferId, result)
                } else {
                    result.error("INVALID_ARGUMENT", "transferId is required", null)
                }
            }

            // Phase 4: Background Receiving & Recovery APIs
            "startBackgroundService" -> {
                val customName = call.argument<String>("customName")
                startBackgroundService(customName, result)
            }
            "stopBackgroundService" -> {
                stopBackgroundService(result)
            }
            "isBackgroundServiceRunning" -> {
                result.success(isBackgroundServiceActive)
            }
            "getRecoveredTransfers" -> {
                handleGetRecoveredTransfers(result)
            }
            "areNotificationsEnabled" -> {
                result.success(notificationHelper.areNotificationsEnabled())
            }

            // Optional NFC Capability & Settings APIs
            "checkNfcStatus" -> {
                result.success(checkNfcStatus())
            }
            "openNfcSettings" -> {
                openNfcSettings(result)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    private fun handleIsSupported(result: MethodChannel.Result) {
        val gmsAvailable = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(appContext) == ConnectionResult.SUCCESS
        val bluetoothAvailable = BluetoothAdapter.getDefaultAdapter() != null
        val isSupported = gmsAvailable && bluetoothAvailable
        result.success(isSupported)
    }

    private fun getRequiredPermissions(): List<String> {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                listOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.NEARBY_WIFI_DEVICES,
                    Manifest.permission.POST_NOTIFICATIONS
                )
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                listOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.ACCESS_FINE_LOCATION
                )
            }
            else -> {
                listOf(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }
    }

    private fun handleCheckPermissions(result: MethodChannel.Result) {
        val required = getRequiredPermissions()
        val missing = required.filter {
            ContextCompat.checkSelfPermission(appContext, it) != PackageManager.PERMISSION_GRANTED
        }

        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        val bluetoothEnabled = bluetoothAdapter?.isEnabled == true

        val locationManager = appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        val locationEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            locationManager?.isLocationEnabled == true
        } else {
            true
        }

        result.success(
            mapOf(
                "granted" to missing.isEmpty(),
                "missing" to missing,
                "bluetoothEnabled" to bluetoothEnabled,
                "locationEnabled" to locationEnabled,
                "notificationsEnabled" to notificationHelper.areNotificationsEnabled()
            )
        )
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        val required = getRequiredPermissions()
        val missing = required.filter {
            ContextCompat.checkSelfPermission(appContext, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isEmpty()) {
            result.success(true)
            return
        }

        val act = currentActivity
        if (act == null) {
            result.error("NO_ACTIVITY", "Cannot request permissions without foreground Activity", null)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(act, missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    fun handlePermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
        }
    }

    private fun handleStartAdvertising(customName: String?, result: MethodChannel.Result?) {
        if (customName != null && customName.isNotBlank()) {
            localEndpointName = customName.trim()
        }

        val advertisingOptions = AdvertisingOptions.Builder()
            .setStrategy(Strategy.P2P_STAR)
            .build()

        connectionsClient.startAdvertising(
            localEndpointName,
            SERVICE_ID,
            connectionLifecycleCallback,
            advertisingOptions
        ).addOnSuccessListener {
            isAdvertising = true
            sendEvent(mapOf("type" to "advertising_state", "isAdvertising" to true))
            result?.success(true)
        }.addOnFailureListener { e ->
            isAdvertising = false
            sendEvent(mapOf("type" to "advertising_state", "isAdvertising" to false))
            sendEvent(mapOf("type" to "error", "code" to "ADVERTISING_FAILED", "message" to e.localizedMessage))
            result?.error("ADVERTISING_FAILED", e.localizedMessage, null)
        }
    }

    private fun handleStopAdvertising(result: MethodChannel.Result?) {
        connectionsClient.stopAdvertising()
        isAdvertising = false
        sendEvent(mapOf("type" to "advertising_state", "isAdvertising" to false))
        result?.success(true)
    }

    private fun handleStartDiscovery(result: MethodChannel.Result) {
        val discoveryOptions = DiscoveryOptions.Builder()
            .setStrategy(Strategy.P2P_STAR)
            .build()

        connectionsClient.startDiscovery(
            SERVICE_ID,
            endpointDiscoveryCallback,
            discoveryOptions
        ).addOnSuccessListener {
            isDiscovering = true
            sendEvent(mapOf("type" to "discovery_state", "isDiscovering" to true))
            result.success(true)
        }.addOnFailureListener { e ->
            isDiscovering = false
            sendEvent(mapOf("type" to "discovery_state", "isDiscovering" to false))
            sendEvent(mapOf("type" to "error", "code" to "DISCOVERY_FAILED", "message" to e.localizedMessage))
            result.error("DISCOVERY_FAILED", e.localizedMessage, null)
        }
    }

    private fun handleStopDiscovery(result: MethodChannel.Result) {
        connectionsClient.stopDiscovery()
        isDiscovering = false
        sendEvent(mapOf("type" to "discovery_state", "isDiscovering" to false))
        result.success(true)
    }

    private fun handleConnect(endpointId: String, result: MethodChannel.Result) {
        connectionsClient.requestConnection(
            localEndpointName,
            endpointId,
            connectionLifecycleCallback
        ).addOnSuccessListener {
            result.success(true)
        }.addOnFailureListener { e ->
            sendEvent(mapOf("type" to "error", "code" to "CONNECT_FAILED", "message" to e.localizedMessage))
            result.error("CONNECT_FAILED", e.localizedMessage, null)
        }
    }

    private fun handleAcceptConnection(endpointId: String, result: MethodChannel.Result?) {
        connectionsClient.acceptConnection(endpointId, payloadCallback)
            .addOnSuccessListener {
                result?.success(true)
            }.addOnFailureListener { e ->
                sendEvent(mapOf("type" to "error", "code" to "ACCEPT_FAILED", "message" to e.localizedMessage))
                result?.error("ACCEPT_FAILED", e.localizedMessage, null)
            }
    }

    private fun handleRejectConnection(endpointId: String, result: MethodChannel.Result?) {
        connectionsClient.rejectConnection(endpointId)
            .addOnSuccessListener {
                result?.success(true)
            }.addOnFailureListener { e ->
                result?.error("REJECT_FAILED", e.localizedMessage, null)
            }
    }

    private fun handleDisconnect(endpointId: String, result: MethodChannel.Result) {
        connectionsClient.disconnectFromEndpoint(endpointId)
        result.success(true)
    }

    private fun handleStopAll(result: MethodChannel.Result) {
        try {
            connectionsClient.stopAllEndpoints()
            connectionsClient.stopDiscovery()
            connectionsClient.stopAdvertising()
            isDiscovering = false
            isAdvertising = false
            cleanupPendingTransfers()
            notificationHelper.cancelAllDropNotifications()
            sendEvent(mapOf("type" to "discovery_state", "isDiscovering" to false))
            sendEvent(mapOf("type" to "advertising_state", "isAdvertising" to false))
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_ALL_FAILED", e.localizedMessage, null)
        }
    }

    // ==========================================
    // Phase 4: Background Receiving Implementation
    // ==========================================

    fun startBackgroundService(customName: String?, result: MethodChannel.Result?) {
        try {
            val intent = Intent(appContext, MusicDropService::class.java).apply {
                action = MusicDropService.ACTION_START
                putExtra(MusicDropService.EXTRA_DEVICE_NAME, customName ?: localEndpointName)
                putExtra(MusicDropService.EXTRA_IS_DISCOVERABLE, true)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }

            isBackgroundServiceActive = true
            if (!isAdvertising) {
                handleStartAdvertising(customName, null)
            }

            sendEvent(mapOf("type" to "background_service_state", "isRunning" to true))
            result?.success(true)
        } catch (e: Exception) {
            isBackgroundServiceActive = false
            sendEvent(mapOf("type" to "background_service_state", "isRunning" to false))
            result?.error("SERVICE_START_FAILED", e.localizedMessage, null)
        }
    }

    fun stopBackgroundService(result: MethodChannel.Result? = null) {
        try {
            val intent = Intent(appContext, MusicDropService::class.java).apply {
                action = MusicDropService.ACTION_STOP
            }
            appContext.stopService(intent)
            isBackgroundServiceActive = false

            sendEvent(mapOf("type" to "background_service_state", "isRunning" to false))
            notificationHelper.cancelAllDropNotifications()
            result?.success(true)
        } catch (e: Exception) {
            result?.error("SERVICE_STOP_FAILED", e.localizedMessage, null)
        }
    }

    private fun handleGetRecoveredTransfers(result: MethodChannel.Result) {
        executor.execute {
            val stagingDir = File(appContext.cacheDir, "music_drop_staging")
            val records = recoveryStore.getPendingTransfers()
            val list = records.map { it.toMap(stagingDir) }
            mainHandler.post {
                result.success(list)
            }
        }
    }

    fun acceptTransferFromNotification(transferId: String?, endpointId: String?) {
        if (endpointId != null) {
            handleAcceptConnection(endpointId, null)
        }
        notificationHelper.cancelNotification(MusicDropNotificationHelper.INCOMING_NOTIFICATION_ID)
        sendEvent(
            mapOf(
                "type" to "notification_action",
                "action" to "accept",
                "transferId" to transferId,
                "endpointId" to endpointId
            )
        )
    }

    fun declineTransferFromNotification(transferId: String?, endpointId: String?) {
        if (endpointId != null) {
            handleRejectConnection(endpointId, null)
        }
        if (transferId != null) {
            val payloadId = transferIdToFilePayloadId[transferId]
            if (payloadId != null) {
                try {
                    connectionsClient.cancelPayload(payloadId)
                } catch (_: Exception) {}
            }
            handleDiscardReceivedFile(transferId, null)
        }
        notificationHelper.cancelNotification(MusicDropNotificationHelper.INCOMING_NOTIFICATION_ID)
        notificationHelper.cancelNotification(MusicDropNotificationHelper.PROGRESS_NOTIFICATION_ID)
        sendEvent(
            mapOf(
                "type" to "notification_action",
                "action" to "decline",
                "transferId" to transferId,
                "endpointId" to endpointId
            )
        )
    }

    fun notifyOpenDropRequested(transferId: String?) {
        sendEvent(
            mapOf(
                "type" to "open_drop_requested",
                "transferId" to transferId
            )
        )
    }

    // ==========================================
    // Optional NFC Support & Event Handlers
    // ==========================================

    fun checkNfcStatus(): String {
        return try {
            val adapter = NfcAdapter.getDefaultAdapter(appContext)
            when {
                adapter == null -> "unsupported"
                !adapter.isEnabled -> "disabled"
                else -> "enabled"
            }
        } catch (_: Exception) {
            "unsupported"
        }
    }

    private fun openNfcSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_NFC_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            if (intent.resolveActivity(appContext.packageManager) != null) {
                appContext.startActivity(intent)
                result.success(true)
            } else {
                val wireIntent = Intent(Settings.ACTION_WIRELESS_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                appContext.startActivity(wireIntent)
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("OPEN_NFC_SETTINGS_FAILED", e.localizedMessage, null)
        }
    }

    fun handleNfcTrigger(data: String) {
        sendEvent(
            mapOf(
                "type" to "nfc_trigger",
                "data" to data
            )
        )
    }

    // ==========================================
    // Phase 2: Payload Transfer Engine Implementation
    // ==========================================

    private fun handleSendMetadata(endpointId: String, metadataJson: String, result: MethodChannel.Result) {
        try {
            val bytes = metadataJson.toByteArray(Charsets.UTF_8)
            if (bytes.size > MAX_METADATA_BYTES) {
                result.error("PAYLOAD_TOO_LARGE", "Metadata exceeds ${MAX_METADATA_BYTES} bytes limit", null)
                return
            }
            val payload = Payload.fromBytes(bytes)
            connectionsClient.sendPayload(endpointId, payload)
                .addOnSuccessListener {
                    result.success(payload.id)
                }
                .addOnFailureListener { e ->
                    result.error("SEND_METADATA_FAILED", e.localizedMessage, null)
                }
        } catch (e: Exception) {
            result.error("SEND_METADATA_ERROR", e.localizedMessage, null)
        }
    }

    private fun handleSendAudioFile(
        endpointId: String,
        filePath: String,
        metadataJsonStr: String,
        result: MethodChannel.Result
    ) {
        executor.execute {
            try {
                val file = File(filePath)
                if (!file.exists() || !file.isFile) {
                    mainHandler.post {
                        result.error("FILE_NOT_FOUND", "Audio file does not exist: $filePath", null)
                    }
                    return@execute
                }

                val ext = file.extension.lowercase()
                if (!SUPPORTED_AUDIO_EXTENSIONS.contains(ext)) {
                    mainHandler.post {
                        result.error("UNSUPPORTED_FORMAT", "Unsupported audio format: .$ext", null)
                    }
                    return@execute
                }

                val fileLength = file.length()
                if (fileLength <= 0 || fileLength > MAX_AUDIO_FILE_BYTES) {
                    mainHandler.post {
                        result.error(
                            "INVALID_FILE_SIZE",
                            "File size ($fileLength bytes) exceeds limit of $MAX_AUDIO_FILE_BYTES bytes",
                            null
                        )
                    }
                    return@execute
                }

                // Streaming SHA-256 calculation
                val expectedSha256 = calculateSha256(FileInputStream(file))

                // Create Nearby file payload
                val filePayload = Payload.fromFile(file)
                val filePayloadId = filePayload.id

                // Parse and enrich metadata JSON with file payload ID, exact size, and SHA-256
                val metaJson = JSONObject(metadataJsonStr)
                val transferId = metaJson.optString("transferId", "md_tx_${System.currentTimeMillis()}")
                metaJson.put("transferId", transferId)
                metaJson.put("filePayloadId", filePayloadId)
                metaJson.put("fileSize", fileLength)
                metaJson.put("fileName", file.name)
                metaJson.put("expectedSha256", expectedSha256)
                metaJson.put("audioFormat", ext)

                val updatedJsonBytes = metaJson.toString().toByteArray(Charsets.UTF_8)
                if (updatedJsonBytes.size > MAX_METADATA_BYTES) {
                    mainHandler.post {
                        result.error("PAYLOAD_TOO_LARGE", "Enriched metadata exceeds size limit", null)
                    }
                    return@execute
                }
                val metaPayload = Payload.fromBytes(updatedJsonBytes)

                transferIdToFilePayloadId[transferId] = filePayloadId
                filePayloadIdToTransferId[filePayloadId] = transferId

                // Send metadata first, then file payload
                connectionsClient.sendPayload(endpointId, metaPayload)
                    .addOnSuccessListener {
                        connectionsClient.sendPayload(endpointId, filePayload)
                            .addOnSuccessListener {
                                val responseData = mapOf(
                                    "transferId" to transferId,
                                    "metaPayloadId" to metaPayload.id,
                                    "filePayloadId" to filePayloadId,
                                    "sha256" to expectedSha256,
                                    "fileSize" to fileLength,
                                    "fileName" to file.name
                                )
                                mainHandler.post { result.success(responseData) }
                            }
                            .addOnFailureListener { e ->
                                mainHandler.post {
                                    result.error("SEND_FILE_FAILED", e.localizedMessage, null)
                                }
                            }
                    }
                    .addOnFailureListener { e ->
                        mainHandler.post {
                            result.error("SEND_METADATA_FAILED", e.localizedMessage, null)
                        }
                    }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("SEND_AUDIO_FILE_ERROR", e.localizedMessage, null)
                }
            }
        }
    }

    private fun handleCancelPayload(payloadId: Long, result: MethodChannel.Result) {
        try {
            connectionsClient.cancelPayload(payloadId)
                .addOnSuccessListener {
                    val transferId = filePayloadIdToTransferId.remove(payloadId)
                    if (transferId != null) {
                        transferIdToFilePayloadId.remove(transferId)
                        stagingFiles.remove(transferId)?.delete()
                        recoveryStore.removeStagedTransfer(transferId)
                    }
                    incomingFilePayloads.remove(payloadId)
                    notificationHelper.cancelNotification(MusicDropNotificationHelper.PROGRESS_NOTIFICATION_ID)
                    result.success(true)
                }
                .addOnFailureListener { e ->
                    result.error("CANCEL_FAILED", e.localizedMessage, null)
                }
        } catch (e: Exception) {
            result.error("CANCEL_ERROR", e.localizedMessage, null)
        }
    }

    private fun handleCommitReceivedFile(
        transferId: String,
        destinationDirStr: String?,
        customName: String?,
        result: MethodChannel.Result
    ) {
        executor.execute {
            try {
                val stagedFile = stagingFiles[transferId]
                if (stagedFile == null || !stagedFile.exists()) {
                    mainHandler.post {
                        result.error("NOT_FOUND", "No verified staged file found for transfer: $transferId", null)
                    }
                    return@execute
                }

                val targetDir = if (!destinationDirStr.isNullOrBlank()) {
                    File(destinationDirStr).apply { mkdirs() }
                } else {
                    currentActivity?.getExternalFilesDir("Music")
                        ?: appContext.getExternalFilesDir("Music")
                        ?: appContext.filesDir
                }

                val desiredName = sanitizeFileName(
                    customName ?: transferIdToSanitizedName[transferId] ?: stagedFile.name
                )
                val destFile = getNonCollidingFile(targetDir, desiredName)

                stagedFile.copyTo(destFile, overwrite = false)
                stagedFile.delete()
                stagingFiles.remove(transferId)
                transferIdToSanitizedName.remove(transferId)
                transferIdToExpectedSha256.remove(transferId)
                transferIdToMetadata.remove(transferId)
                recoveryStore.removeStagedTransfer(transferId)
                notificationHelper.cancelNotification(MusicDropNotificationHelper.COMPLETION_NOTIFICATION_ID)

                mainHandler.post {
                    result.success(destFile.absolutePath)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("COMMIT_FAILED", e.localizedMessage, null)
                }
            }
        }
    }

    private fun handleDiscardReceivedFile(transferId: String, result: MethodChannel.Result?) {
        val stagedFile = stagingFiles.remove(transferId)
        if (stagedFile != null && stagedFile.exists()) {
            stagedFile.delete()
        }
        transferIdToSanitizedName.remove(transferId)
        transferIdToExpectedSha256.remove(transferId)
        transferIdToMetadata.remove(transferId)
        recoveryStore.removeStagedTransfer(transferId)
        notificationHelper.cancelNotification(MusicDropNotificationHelper.COMPLETION_NOTIFICATION_ID)

        val filePayloadId = transferIdToFilePayloadId.remove(transferId)
        if (filePayloadId != null) {
            filePayloadIdToTransferId.remove(filePayloadId)
            incomingFilePayloads.remove(filePayloadId)
        }
        result?.success(true)
    }

    private fun sanitizeFileName(fileName: String?, fallbackExt: String = "mp3"): String {
        if (fileName.isNullOrBlank()) {
            return "miee_${System.currentTimeMillis()}.$fallbackExt"
        }
        val base = File(fileName).name.trim()
        val cleaned = base.replace(Regex("[\\x00-\\x1F\\x7F/\\\\:*?\"<>|]"), "_")
        val dot = cleaned.lastIndexOf('.')
        val ext = if (dot != -1 && dot < cleaned.length - 1) {
            cleaned.substring(dot + 1).lowercase()
        } else {
            fallbackExt
        }
        val safeExt = if (SUPPORTED_AUDIO_EXTENSIONS.contains(ext)) ext else fallbackExt
        val nameWithoutExt = if (dot != -1) cleaned.substring(0, dot) else cleaned
        val clampedName = if (nameWithoutExt.length > 60) nameWithoutExt.substring(0, 60) else nameWithoutExt
        return "$clampedName.$safeExt"
    }

    private fun getNonCollidingFile(targetDir: File, desiredName: String): File {
        var candidate = File(targetDir, desiredName)
        if (!candidate.exists()) return candidate

        val dot = desiredName.lastIndexOf('.')
        val baseName = if (dot != -1) desiredName.substring(0, dot) else desiredName
        val ext = if (dot != -1) desiredName.substring(dot) else ""

        var counter = 1
        while (candidate.exists() && counter < 10000) {
            candidate = File(targetDir, "$baseName ($counter)$ext")
            counter++
        }
        return candidate
    }

    private fun calculateSha256(inputStream: InputStream): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(16384)
        var bytesRead: Int
        try {
            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        } finally {
            try {
                inputStream.close()
            } catch (_: Exception) {}
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun cleanupPendingTransfers() {
        incomingFilePayloads.clear()
        filePayloadIdToTransferId.clear()
        transferIdToFilePayloadId.clear()
        transferIdToExpectedSha256.clear()
        transferIdToSanitizedName.clear()
        transferIdToMetadata.clear()
        stagingFiles.values.forEach {
            try {
                if (it.exists()) it.delete()
            } catch (_: Exception) {}
        }
        stagingFiles.clear()
    }

    fun destroy() {
        try {
            connectionsClient.stopAllEndpoints()
            connectionsClient.stopDiscovery()
            connectionsClient.stopAdvertising()
        } catch (_: Exception) {}
        cleanupPendingTransfers()
        notificationHelper.cancelAllDropNotifications()
        try {
            executor.shutdownNow()
        } catch (_: Exception) {}
        eventSink = null
    }

    // Callbacks for Endpoint Discovery
    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            sendEvent(
                mapOf(
                    "type" to "endpoint_found",
                    "endpointId" to endpointId,
                    "endpointName" to info.endpointName,
                    "serviceId" to info.serviceId
                )
            )
        }

        override fun onEndpointLost(endpointId: String) {
            sendEvent(
                mapOf(
                    "type" to "endpoint_lost",
                    "endpointId" to endpointId
                )
            )
        }
    }

    // Callbacks for Connection Negotiation & Handshake
    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            sendEvent(
                mapOf(
                    "type" to "connection_initiated",
                    "endpointId" to endpointId,
                    "endpointName" to info.endpointName,
                    "authDigits" to info.authenticationDigits,
                    "isIncoming" to info.isIncomingConnection
                )
            )

            // When in background or background service active, display heads-up notification
            if (!isAppInForeground || isBackgroundServiceActive) {
                val notif = notificationHelper.buildIncomingRequestNotification(
                    transferId = "init_$endpointId",
                    endpointId = endpointId,
                    deviceName = info.endpointName,
                    trackTitle = "Nearby Song",
                    artist = "Connecting..."
                )
                notificationHelper.postNotification(MusicDropNotificationHelper.INCOMING_NOTIFICATION_ID, notif)
            }
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            val status = result.status
            val isSuccess = status.isSuccess
            sendEvent(
                mapOf(
                    "type" to "connection_result",
                    "endpointId" to endpointId,
                    "statusCode" to status.statusCode,
                    "isSuccess" to isSuccess,
                    "statusMessage" to (status.statusMessage ?: "")
                )
            )

            if (!isSuccess) {
                notificationHelper.cancelNotification(MusicDropNotificationHelper.INCOMING_NOTIFICATION_ID)
            }
        }

        override fun onDisconnected(endpointId: String) {
            sendEvent(
                mapOf(
                    "type" to "disconnected",
                    "endpointId" to endpointId
                )
            )
            notificationHelper.cancelNotification(MusicDropNotificationHelper.INCOMING_NOTIFICATION_ID)
            notificationHelper.cancelNotification(MusicDropNotificationHelper.PROGRESS_NOTIFICATION_ID)
        }
    }

    // Callbacks for Payload Transfer & Integrity Pipeline
    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            when (payload.type) {
                Payload.Type.BYTES -> {
                    val bytes = payload.asBytes()
                    if (bytes == null || bytes.size > MAX_METADATA_BYTES) {
                        return
                    }
                    val jsonStr = String(bytes, Charsets.UTF_8)
                    try {
                        val metaJson = JSONObject(jsonStr)
                        val transferId = metaJson.optString("transferId")
                        val filePayloadId = if (metaJson.has("filePayloadId")) metaJson.getLong("filePayloadId") else null
                        val expectedSha256 = metaJson.optString("expectedSha256", null)
                        val fileName = metaJson.optString("fileName", null)
                        val title = metaJson.optString("title", "Unknown Title")
                        val artist = metaJson.optString("artist", "Unknown Artist")
                        val album = if (metaJson.has("album")) metaJson.optString("album") else null

                        if (transferId.isNotBlank()) {
                            transferIdToMetadata[transferId] = mapOf(
                                "title" to title,
                                "artist" to artist,
                                "album" to (album ?: "")
                            )
                        }

                        if (transferId.isNotBlank() && filePayloadId != null) {
                            filePayloadIdToTransferId[filePayloadId] = transferId
                            transferIdToFilePayloadId[transferId] = filePayloadId
                            if (!expectedSha256.isNullOrBlank()) {
                                transferIdToExpectedSha256[transferId] = expectedSha256
                            }
                            if (!fileName.isNullOrBlank()) {
                                transferIdToSanitizedName[transferId] = sanitizeFileName(fileName)
                            }
                        }

                        // If backgrounded, update incoming notification with rich track metadata
                        if (!isAppInForeground || isBackgroundServiceActive) {
                            val notif = notificationHelper.buildIncomingRequestNotification(
                                transferId = transferId,
                                endpointId = endpointId,
                                deviceName = "Nearby Miee Peer",
                                trackTitle = title,
                                artist = artist
                            )
                            notificationHelper.postNotification(MusicDropNotificationHelper.INCOMING_NOTIFICATION_ID, notif)
                        }
                    } catch (_: Exception) {}

                    sendEvent(
                        mapOf(
                            "type" to "payload_received",
                            "payloadType" to "bytes",
                            "endpointId" to endpointId,
                            "payloadId" to payload.id,
                            "data" to jsonStr
                        )
                    )
                }

                Payload.Type.FILE -> {
                    incomingFilePayloads[payload.id] = payload
                    sendEvent(
                        mapOf(
                            "type" to "payload_received",
                            "payloadType" to "file",
                            "endpointId" to endpointId,
                            "payloadId" to payload.id
                        )
                    )
                }

                Payload.Type.STREAM -> {}
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            val payloadId = update.payloadId
            val bytesTransferred = update.bytesTransferred
            val totalBytes = update.totalBytes

            when (update.status) {
                PayloadTransferUpdate.Status.IN_PROGRESS -> {
                    sendEvent(
                        mapOf(
                            "type" to "payload_progress",
                            "endpointId" to endpointId,
                            "payloadId" to payloadId,
                            "bytesTransferred" to bytesTransferred,
                            "totalBytes" to totalBytes,
                            "status" to "in_progress"
                        )
                    )

                    // Throttle background progress updates (at most once every 600ms)
                    val transferId = filePayloadIdToTransferId[payloadId]
                    if (transferId != null && (!isAppInForeground || isBackgroundServiceActive)) {
                        val now = System.currentTimeMillis()
                        val lastTime = lastProgressNotificationTime[transferId] ?: 0L
                        if (now - lastTime > 600) {
                            lastProgressNotificationTime[transferId] = now
                            val percent = if (totalBytes > 0) ((bytesTransferred * 100) / totalBytes).toInt() else 0
                            val meta = transferIdToMetadata[transferId]
                            val title = meta?.get("title") ?: "Audio File"
                            val notif = notificationHelper.buildProgressNotification(
                                transferId = transferId,
                                trackTitle = title,
                                percent = percent,
                                bytesTransferred = bytesTransferred,
                                totalBytes = totalBytes
                            )
                            notificationHelper.postNotification(MusicDropNotificationHelper.PROGRESS_NOTIFICATION_ID, notif)
                        }
                    }
                }

                PayloadTransferUpdate.Status.SUCCESS -> {
                    sendEvent(
                        mapOf(
                            "type" to "payload_progress",
                            "endpointId" to endpointId,
                            "payloadId" to payloadId,
                            "bytesTransferred" to totalBytes,
                            "totalBytes" to totalBytes,
                            "status" to "success"
                        )
                    )

                    notificationHelper.cancelNotification(MusicDropNotificationHelper.PROGRESS_NOTIFICATION_ID)

                    val filePayload = incomingFilePayloads.remove(payloadId)
                    val transferId = filePayloadIdToTransferId[payloadId]

                    if (filePayload != null && transferId != null) {
                        processIncomingFilePayload(transferId, payloadId, filePayload)
                    }
                }

                PayloadTransferUpdate.Status.CANCELED -> {
                    incomingFilePayloads.remove(payloadId)
                    val transferId = filePayloadIdToTransferId.remove(payloadId)
                    if (transferId != null) {
                        stagingFiles.remove(transferId)?.delete()
                        recoveryStore.removeStagedTransfer(transferId)
                    }
                    notificationHelper.cancelNotification(MusicDropNotificationHelper.PROGRESS_NOTIFICATION_ID)
                    sendEvent(
                        mapOf(
                            "type" to "payload_progress",
                            "endpointId" to endpointId,
                            "payloadId" to payloadId,
                            "bytesTransferred" to bytesTransferred,
                            "totalBytes" to totalBytes,
                            "status" to "cancelled"
                        )
                    )
                }

                PayloadTransferUpdate.Status.FAILURE -> {
                    incomingFilePayloads.remove(payloadId)
                    val transferId = filePayloadIdToTransferId.remove(payloadId)
                    if (transferId != null) {
                        stagingFiles.remove(transferId)?.delete()
                        recoveryStore.removeStagedTransfer(transferId)
                    }
                    notificationHelper.cancelNotification(MusicDropNotificationHelper.PROGRESS_NOTIFICATION_ID)
                    sendEvent(
                        mapOf(
                            "type" to "payload_progress",
                            "endpointId" to endpointId,
                            "payloadId" to payloadId,
                            "bytesTransferred" to bytesTransferred,
                            "totalBytes" to totalBytes,
                            "status" to "failure"
                        )
                    )
                }
            }
        }
    }

    private fun processIncomingFilePayload(transferId: String, payloadId: Long, filePayload: Payload) {
        executor.execute {
            try {
                sendEvent(
                    mapOf(
                        "type" to "transfer_verifying",
                        "transferId" to transferId,
                        "payloadId" to payloadId
                    )
                )

                val fileHolder = filePayload.asFile()
                val javaFile = fileHolder?.asJavaFile()
                val inputStream: InputStream? = if (javaFile != null && javaFile.exists()) {
                    FileInputStream(javaFile)
                } else {
                    fileHolder?.asParcelFileDescriptor()?.fileDescriptor?.let {
                        FileInputStream(it)
                    }
                }

                if (inputStream == null) {
                    sendEvent(
                        mapOf(
                            "type" to "transfer_failed",
                            "transferId" to transferId,
                            "payloadId" to payloadId,
                            "reason" to "FILE_ACCESS_ERROR",
                            "message" to "Unable to access received file descriptor."
                        )
                    )
                    return@execute
                }

                // Stage into app cache
                val stagingDir = File(appContext.cacheDir, "music_drop_staging").apply { mkdirs() }
                val sanitizedName = transferIdToSanitizedName[transferId] ?: "miee_audio.mp3"
                val stagingFileName = "${transferId}_$sanitizedName"
                val stagingFile = File(stagingDir, stagingFileName)

                val digest = MessageDigest.getInstance("SHA-256")
                val buffer = ByteArray(16384)
                var bytesRead: Int
                val outputStream = FileOutputStream(stagingFile)

                try {
                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                        digest.update(buffer, 0, bytesRead)
                        outputStream.write(buffer, 0, bytesRead)
                    }
                    outputStream.flush()
                } finally {
                    try { inputStream.close() } catch (_: Exception) {}
                    try { outputStream.close() } catch (_: Exception) {}
                    try {
                        if (javaFile != null && javaFile.exists()) {
                            javaFile.delete()
                        }
                    } catch (_: Exception) {}
                }

                val calculatedSha256 = digest.digest().joinToString("") { "%02x".format(it) }
                val expectedSha256 = transferIdToExpectedSha256[transferId]

                // Verification check
                if (!expectedSha256.isNullOrBlank() && !calculatedSha256.equals(expectedSha256, ignoreCase = true)) {
                    stagingFile.delete()
                    sendEvent(
                        mapOf(
                            "type" to "transfer_failed",
                            "transferId" to transferId,
                            "payloadId" to payloadId,
                            "reason" to "CHECKSUM_MISMATCH",
                            "message" to "SHA-256 checksum mismatch: expected $expectedSha256, got $calculatedSha256"
                        )
                    )
                    val meta = transferIdToMetadata[transferId]
                    val notif = notificationHelper.buildFailureNotification(
                        meta?.get("title") ?: "Audio Transfer",
                        "Checksum mismatch verification failure"
                    )
                    notificationHelper.postNotification(MusicDropNotificationHelper.FAILURE_NOTIFICATION_ID, notif)
                    return@execute
                }

                // Verification succeeded: stage file and save to recovery store
                stagingFiles[transferId] = stagingFile
                val meta = transferIdToMetadata[transferId]
                val title = meta?.get("title") ?: "Received Song"
                val artist = meta?.get("artist") ?: "Unknown Artist"
                val album = meta?.get("album")

                recoveryStore.recordPendingStagedTransfer(
                    MusicDropRecoveryStore.StagedTransferRecord(
                        transferId = transferId,
                        stagingFileName = stagingFileName,
                        title = title,
                        artist = artist,
                        album = album,
                        expectedSha256 = calculatedSha256,
                        fileSize = stagingFile.length(),
                        timestamp = System.currentTimeMillis(),
                        isVerified = true
                    )
                )

                sendEvent(
                    mapOf(
                        "type" to "transfer_completed",
                        "transferId" to transferId,
                        "payloadId" to payloadId,
                        "stagingPath" to stagingFile.absolutePath,
                        "sha256" to calculatedSha256
                    )
                )

                // If backgrounded, display consent-required completion notification
                if (!isAppInForeground || isBackgroundServiceActive) {
                    val notif = notificationHelper.buildCompletionNotification(
                        transferId = transferId,
                        trackTitle = title,
                        artist = artist
                    )
                    notificationHelper.postNotification(MusicDropNotificationHelper.COMPLETION_NOTIFICATION_ID, notif)
                }
            } catch (e: Exception) {
                sendEvent(
                    mapOf(
                        "type" to "transfer_failed",
                        "transferId" to transferId,
                        "payloadId" to payloadId,
                        "reason" to "VERIFICATION_ERROR",
                        "message" to (e.localizedMessage ?: "Unknown file processing error")
                    )
                )
            }
        }
    }
}
