package com.example.miee.musicdrop

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Isolated native bridge for Google Nearby Connections in Miee Music Drop.
 * Handles platform compatibility, runtime permissions, discovery, advertising,
 * and connection negotiation without affecting audio playback or existing UI.
 */
class MusicDropManager(private val activity: Activity) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val CHANNEL_METHODS = "com.example.miee/music_drop"
        const val CHANNEL_EVENTS = "com.example.miee/music_drop_events"
        const val SERVICE_ID = "com.example.miee.music_drop"
        const val PERMISSION_REQUEST_CODE = 4129
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private val connectionsClient = Nearby.getConnectionsClient(activity)

    private var isAdvertising = false
    private var isDiscovering = false
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var localEndpointName: String = "Miee (${Build.MODEL})"

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
        val gmsAvailable = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity) == ConnectionResult.SUCCESS
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
                    Manifest.permission.NEARBY_WIFI_DEVICES
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
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }

        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        val bluetoothEnabled = bluetoothAdapter?.isEnabled == true

        val locationManager = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
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
                "locationEnabled" to locationEnabled
            )
        )
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        val required = getRequiredPermissions()
        val missing = required.filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isEmpty()) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    fun handlePermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
        }
    }

    private fun handleStartAdvertising(customName: String?, result: MethodChannel.Result) {
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
            result.success(true)
        }.addOnFailureListener { e ->
            isAdvertising = false
            sendEvent(mapOf("type" to "advertising_state", "isAdvertising" to false))
            sendEvent(mapOf("type" to "error", "code" to "ADVERTISING_FAILED", "message" to e.localizedMessage))
            result.error("ADVERTISING_FAILED", e.localizedMessage, null)
        }
    }

    private fun handleStopAdvertising(result: MethodChannel.Result) {
        connectionsClient.stopAdvertising()
        isAdvertising = false
        sendEvent(mapOf("type" to "advertising_state", "isAdvertising" to false))
        result.success(true)
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

    private fun handleAcceptConnection(endpointId: String, result: MethodChannel.Result) {
        connectionsClient.acceptConnection(endpointId, payloadCallback)
            .addOnSuccessListener {
                result.success(true)
            }.addOnFailureListener { e ->
                sendEvent(mapOf("type" to "error", "code" to "ACCEPT_FAILED", "message" to e.localizedMessage))
                result.error("ACCEPT_FAILED", e.localizedMessage, null)
            }
    }

    private fun handleRejectConnection(endpointId: String, result: MethodChannel.Result) {
        connectionsClient.rejectConnection(endpointId)
            .addOnSuccessListener {
                result.success(true)
            }.addOnFailureListener { e ->
                result.error("REJECT_FAILED", e.localizedMessage, null)
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
            sendEvent(mapOf("type" to "discovery_state", "isDiscovering" to false))
            sendEvent(mapOf("type" to "advertising_state", "isAdvertising" to false))
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_ALL_FAILED", e.localizedMessage, null)
        }
    }

    fun destroy() {
        try {
            connectionsClient.stopAllEndpoints()
            connectionsClient.stopDiscovery()
            connectionsClient.stopAdvertising()
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
        }

        override fun onDisconnected(endpointId: String) {
            sendEvent(
                mapOf(
                    "type" to "disconnected",
                    "endpointId" to endpointId
                )
            )
        }
    }

    // Stub payload callback for Phase 1 connection negotiation
    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            // Phase 1 foundation: payload receiving stub
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            // Phase 1 foundation: payload progress stub
        }
    }
}
