package com.example.project_xp

import android.app.AlarmManager
import android.app.NotificationManager
import android.annotation.TargetApi
import android.content.Context
import android.location.LocationManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TetheringInterface
import android.net.TetheringManager
import android.nfc.NfcAdapter
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.function.Consumer

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val DEVICE_STATUS_CHANNEL =
            "project_xp/device_status"
    }

    private var screenRecordingCallback:
        Consumer<Int>? = null

    private var screenRecordingState:
        Int? = null

    private var hotspotState:
        Boolean? = null

    private var tetheringObserver:
        Any? = null

    override fun onCreate(
        savedInstanceState: Bundle?,
    ) {
        super.onCreate(
            savedInstanceState,
        )

        registerScreenRecordingObserver()
        registerHotspotObserver()
    }

    override fun onDestroy() {
        unregisterHotspotObserver()
        unregisterScreenRecordingObserver()

        super.onDestroy()
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine,
    ) {
        super.configureFlutterEngine(
            flutterEngine,
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_STATUS_CHANNEL,
        ).setMethodCallHandler {
                call,
                result,
            ->

            when (call.method) {
                "getDeviceStatus" -> {
                    result.success(
                        buildDeviceStatus(),
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // ========================================================================
    // SNAPSHOT UNIVERSEL
    // ========================================================================

    private fun buildDeviceStatus():
        Map<String, Any?> {
        val status =
            mutableMapOf<String, Any?>()

        status["platform"] =
            "android"

        status["sdkInt"] =
            Build.VERSION.SDK_INT

        status["manufacturer"] =
            Build.MANUFACTURER

        status["model"] =
            Build.MODEL

        status["airplaneMode"] =
            readAirplaneMode()

        status["dndMode"] =
            readDoNotDisturbMode()

        status["ringerMode"] =
            readRingerMode()

        val nfc =
            readNfcState()

        status["nfcAvailable"] =
            nfc.first

        status["nfcEnabled"] =
            nfc.second

        status["powerSaveMode"] =
            readPowerSaveMode()

        status["deviceIdleMode"] =
            readDeviceIdleMode()

        status["dataSaverMode"] =
            readDataSaverMode()

        status["vpnActive"] =
            readVpnActive()

        status["locationEnabled"] =
            readLocationEnabled()

        status["rotationLocked"] =
            readRotationLocked()

        status["nextAlarmAt"] =
            readNextAlarmAt()

        status["screenRecordingSupported"] =
            Build.VERSION.SDK_INT >= 35

        status["screenRecordingActive"] =
            if (
                Build.VERSION.SDK_INT >= 35
            ) {
                screenRecordingState ==
                    WindowManager
                        .SCREEN_RECORDING_STATE_VISIBLE
            } else {
                null
            }

        // Depuis Android 16 / API 36, Android expose enfin
        // publiquement l'état des interfaces actuellement partagées.
        // Sur les versions plus anciennes, on laisse l'état inconnu
        // plutôt que d'utiliser des API privées constructeur.
        status["hotspotReadable"] =
            Build.VERSION.SDK_INT >= 36

        status["hotspotActive"] =
            if (
                Build.VERSION.SDK_INT >= 36
            ) {
                hotspotState
            } else {
                null
            }

        return status
    }

    // ========================================================================
    // MODE AVION
    // ========================================================================

    private fun readAirplaneMode():
        Boolean {
        return try {
            Settings.Global.getInt(
                contentResolver,
                Settings.Global
                    .AIRPLANE_MODE_ON,
                0,
            ) == 1
        } catch (
            error: Exception,
        ) {
            false
        }
    }

    // ========================================================================
    // NE PAS DÉRANGER / ZEN ANDROID STANDARD
    // ========================================================================

    private fun readDoNotDisturbMode():
        String {
        return try {
            val manager =
                getSystemService(
                    Context
                        .NOTIFICATION_SERVICE,
                ) as NotificationManager

            when (
                manager
                    .currentInterruptionFilter
            ) {
                NotificationManager
                    .INTERRUPTION_FILTER_ALL ->
                    "all"

                NotificationManager
                    .INTERRUPTION_FILTER_PRIORITY ->
                    "priority"

                NotificationManager
                    .INTERRUPTION_FILTER_ALARMS ->
                    "alarms"

                NotificationManager
                    .INTERRUPTION_FILTER_NONE ->
                    "none"

                else ->
                    "unknown"
            }
        } catch (
            error: Exception,
        ) {
            "unknown"
        }
    }

    // ========================================================================
    // SONNERIE / VIBREUR / SILENCIEUX
    // ========================================================================

    private fun readRingerMode():
        String {
        return try {
            val audioManager =
                getSystemService(
                    Context.AUDIO_SERVICE,
                ) as AudioManager

            when (
                audioManager.ringerMode
            ) {
                AudioManager
                    .RINGER_MODE_SILENT ->
                    "silent"

                AudioManager
                    .RINGER_MODE_VIBRATE ->
                    "vibrate"

                AudioManager
                    .RINGER_MODE_NORMAL ->
                    "normal"

                else ->
                    "unknown"
            }
        } catch (
            error: Exception,
        ) {
            "unknown"
        }
    }

    // ========================================================================
    // NFC
    // ========================================================================

    private fun readNfcState():
        Pair<Boolean, Boolean?> {
        return try {
            val adapter =
                NfcAdapter
                    .getDefaultAdapter(
                        this,
                    )

            if (adapter == null) {
                Pair(
                    false,
                    null,
                )
            } else {
                Pair(
                    true,
                    adapter.isEnabled,
                )
            }
        } catch (
            error: Exception,
        ) {
            Pair(
                false,
                null,
            )
        }
    }

    // ========================================================================
    // ÉCONOMIE D'ÉNERGIE / DOZE
    // ========================================================================

    private fun readPowerSaveMode():
        Boolean {
        return try {
            val powerManager =
                getSystemService(
                    Context.POWER_SERVICE,
                ) as PowerManager

            powerManager
                .isPowerSaveMode
        } catch (
            error: Exception,
        ) {
            false
        }
    }

    private fun readDeviceIdleMode():
        Boolean {
        return try {
            val powerManager =
                getSystemService(
                    Context.POWER_SERVICE,
                ) as PowerManager

            powerManager
                .isDeviceIdleMode
        } catch (
            error: Exception,
        ) {
            false
        }
    }

    // ========================================================================
    // ÉCONOMISEUR DE DONNÉES
    // ========================================================================

    private fun readDataSaverMode():
        String {
        return try {
            val connectivityManager =
                getSystemService(
                    Context
                        .CONNECTIVITY_SERVICE,
                ) as ConnectivityManager

            when (
                connectivityManager
                    .restrictBackgroundStatus
            ) {
                ConnectivityManager
                    .RESTRICT_BACKGROUND_STATUS_ENABLED ->
                    "enabled"

                ConnectivityManager
                    .RESTRICT_BACKGROUND_STATUS_WHITELISTED ->
                    "whitelisted"

                ConnectivityManager
                    .RESTRICT_BACKGROUND_STATUS_DISABLED ->
                    "disabled"

                else ->
                    "unknown"
            }
        } catch (
            error: Exception,
        ) {
            "unknown"
        }
    }

    // ========================================================================
    // VPN
    // ========================================================================

    private fun readVpnActive():
        Boolean {
        return try {
            val connectivityManager =
                getSystemService(
                    Context
                        .CONNECTIVITY_SERVICE,
                ) as ConnectivityManager

            connectivityManager
                .allNetworks
                .any {
                    network ->

                    val capabilities =
                        connectivityManager
                            .getNetworkCapabilities(
                                network,
                            )

                    capabilities
                        ?.hasTransport(
                            NetworkCapabilities
                                .TRANSPORT_VPN,
                        ) == true
                }
        } catch (
            error: Exception,
        ) {
            false
        }
    }

    // ========================================================================
    // LOCALISATION
    // ========================================================================

    private fun readLocationEnabled():
        Boolean? {
        return try {
            val locationManager =
                getSystemService(
                    Context
                        .LOCATION_SERVICE,
                ) as LocationManager

            if (
                Build.VERSION.SDK_INT >= 28
            ) {
                locationManager
                    .isLocationEnabled
            } else {
                locationManager
                    .isProviderEnabled(
                        LocationManager
                            .GPS_PROVIDER,
                    ) ||
                    locationManager
                        .isProviderEnabled(
                            LocationManager
                                .NETWORK_PROVIDER,
                        )
            }
        } catch (
            error: Exception,
        ) {
            null
        }
    }

    // ========================================================================
    // VERROUILLAGE ROTATION
    // ========================================================================

    private fun readRotationLocked():
        Boolean? {
        return try {
            val autoRotate =
                Settings.System.getInt(
                    contentResolver,
                    Settings.System
                        .ACCELEROMETER_ROTATION,
                    1,
                ) == 1

            !autoRotate
        } catch (
            error: Exception,
        ) {
            null
        }
    }

    // ========================================================================
    // PROCHAINE ALARME
    // ========================================================================

    private fun readNextAlarmAt():
        Long? {
        return try {
            val alarmManager =
                getSystemService(
                    Context.ALARM_SERVICE,
                ) as AlarmManager

            alarmManager
                .nextAlarmClock
                ?.triggerTime
        } catch (
            error: Exception,
        ) {
            null
        }
    }

    // ========================================================================
    // POINT D'ACCÈS / PARTAGE DE CONNEXION — ANDROID 16 / API 36+
    // ========================================================================

    private fun registerHotspotObserver() {
        if (
            Build.VERSION.SDK_INT < 36 ||
            tetheringObserver != null
        ) {
            return
        }

        try {
            val observer =
                Api36TetheringObserver(
                    this,
                ) {
                    active ->

                    hotspotState =
                        active
                }

            observer.register()

            tetheringObserver =
                observer
        } catch (
            error: Exception,
        ) {
            tetheringObserver =
                null

            hotspotState =
                null
        }
    }

    private fun unregisterHotspotObserver() {
        if (
            Build.VERSION.SDK_INT < 36
        ) {
            return
        }

        val observer =
            tetheringObserver
                as? Api36TetheringObserver
                ?: return

        try {
            observer.unregister()
        } catch (
            error: Exception,
        ) {
            // Rien à faire.
        }

        tetheringObserver =
            null

        hotspotState =
            null
    }

    @TargetApi(36)
    private class Api36TetheringObserver(
        context: Context,
        private val onStateChanged:
            (Boolean) -> Unit,
    ) {
        private val tetheringManager =
            context.getSystemService(
                TetheringManager::class.java,
            )

        private val executor =
            context.mainExecutor

        private val callback =
            object :
                TetheringManager
                    .TetheringEventCallback {
                override fun onTetheredInterfacesChanged(
                    interfaces:
                        Set<TetheringInterface>,
                ) {
                    onStateChanged(
                        interfaces.isNotEmpty(),
                    )
                }
            }

        fun register() {
            tetheringManager
                .registerTetheringEventCallback(
                    executor,
                    callback,
                )
        }

        fun unregister() {
            tetheringManager
                .unregisterTetheringEventCallback(
                    callback,
                )
        }
    }

    // ========================================================================
    // ENREGISTREMENT D'ÉCRAN — ANDROID 15 / API 35+
    // ========================================================================

    private fun registerScreenRecordingObserver() {
        if (
            Build.VERSION.SDK_INT < 35 ||
            screenRecordingCallback != null
        ) {
            return
        }

        try {
            val windowManager =
                getSystemService(
                    WindowManager::class.java,
                )

            val callback =
                Consumer<Int> {
                    state ->

                    screenRecordingState =
                        state
                }

            screenRecordingState =
                windowManager
                    .addScreenRecordingCallback(
                        mainExecutor,
                        callback,
                    )

            screenRecordingCallback =
                callback
        } catch (
            error: Exception,
        ) {
            screenRecordingCallback =
                null

            screenRecordingState =
                null
        }
    }

    private fun unregisterScreenRecordingObserver() {
        if (
            Build.VERSION.SDK_INT < 35
        ) {
            return
        }

        val callback =
            screenRecordingCallback
                ?: return

        try {
            val windowManager =
                getSystemService(
                    WindowManager::class.java,
                )

            windowManager
                .removeScreenRecordingCallback(
                    callback,
                )
        } catch (
            error: Exception,
        ) {
            // Rien à faire.
        }

        screenRecordingCallback =
            null

        screenRecordingState =
            null
    }
}