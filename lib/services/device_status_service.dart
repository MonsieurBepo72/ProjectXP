import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceStatusSnapshot {
  const DeviceStatusSnapshot({
    required this.platform,
    required this.available,
    this.sdkInt,
    this.manufacturer,
    this.model,
    this.airplaneMode,
    this.dndMode = 'unknown',
    this.ringerMode = 'unknown',
    this.nfcAvailable = false,
    this.nfcEnabled,
    this.powerSaveMode,
    this.deviceIdleMode,
    this.dataSaverMode = 'unknown',
    this.vpnActive,
    this.locationEnabled,
    this.rotationLocked,
    this.nextAlarmAt,
    this.screenRecordingSupported = false,
    this.screenRecordingActive,
    this.hotspotReadable = false,
    this.hotspotActive,
  });

  final String platform;
  final bool available;

  final int? sdkInt;
  final String? manufacturer;
  final String? model;

  final bool? airplaneMode;

  /// all | priority | alarms | none | unknown
  final String dndMode;

  /// normal | vibrate | silent | unknown
  final String ringerMode;

  final bool nfcAvailable;
  final bool? nfcEnabled;

  final bool? powerSaveMode;
  final bool? deviceIdleMode;

  /// enabled | whitelisted | disabled | unknown
  final String dataSaverMode;

  final bool? vpnActive;
  final bool? locationEnabled;
  final bool? rotationLocked;

  final DateTime? nextAlarmAt;

  final bool screenRecordingSupported;
  final bool? screenRecordingActive;

  final bool hotspotReadable;
  final bool? hotspotActive;

  bool get dndEnabled {
    return dndMode != 'all' &&
        dndMode != 'unknown';
  }

  bool get isSilent {
    return ringerMode == 'silent';
  }

  bool get isVibrate {
    return ringerMode == 'vibrate';
  }

  bool get dataSaverEnabled {
    return dataSaverMode == 'enabled';
  }

  static DeviceStatusSnapshot unsupported({
    String platform = 'unsupported',
  }) {
    return DeviceStatusSnapshot(
      platform: platform,
      available: false,
    );
  }

  factory DeviceStatusSnapshot.fromMap(
    Map<dynamic, dynamic> map,
  ) {
    final int? alarmMilliseconds =
        _asInt(
      map['nextAlarmAt'],
    );

    return DeviceStatusSnapshot(
      platform:
          map['platform']?.toString() ??
              'android',
      available: true,
      sdkInt:
          _asInt(
        map['sdkInt'],
      ),
      manufacturer:
          map['manufacturer']?.toString(),
      model:
          map['model']?.toString(),
      airplaneMode:
          _asBool(
        map['airplaneMode'],
      ),
      dndMode:
          map['dndMode']?.toString() ??
              'unknown',
      ringerMode:
          map['ringerMode']?.toString() ??
              'unknown',
      nfcAvailable:
          _asBool(
            map['nfcAvailable'],
          ) ??
          false,
      nfcEnabled:
          _asBool(
        map['nfcEnabled'],
      ),
      powerSaveMode:
          _asBool(
        map['powerSaveMode'],
      ),
      deviceIdleMode:
          _asBool(
        map['deviceIdleMode'],
      ),
      dataSaverMode:
          map['dataSaverMode']
                  ?.toString() ??
              'unknown',
      vpnActive:
          _asBool(
        map['vpnActive'],
      ),
      locationEnabled:
          _asBool(
        map['locationEnabled'],
      ),
      rotationLocked:
          _asBool(
        map['rotationLocked'],
      ),
      nextAlarmAt:
          alarmMilliseconds == null
              ? null
              : DateTime
                  .fromMillisecondsSinceEpoch(
                  alarmMilliseconds,
                ),
      screenRecordingSupported:
          _asBool(
            map[
                'screenRecordingSupported'],
          ) ??
          false,
      screenRecordingActive:
          _asBool(
        map['screenRecordingActive'],
      ),
      hotspotReadable:
          _asBool(
            map['hotspotReadable'],
          ) ??
          false,
      hotspotActive:
          _asBool(
        map['hotspotActive'],
      ),
    );
  }

  static bool? _asBool(
    dynamic value,
  ) {
    if (value is bool) {
      return value;
    }

    return null;
  }

  static int? _asInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    );
  }
}

class DeviceStatusService {
  DeviceStatusService._();

  static final DeviceStatusService instance =
      DeviceStatusService._();

  static const MethodChannel _channel =
      MethodChannel(
    'project_xp/device_status',
  );

  Future<DeviceStatusSnapshot>
      getSnapshot() async {
    if (kIsWeb) {
      return DeviceStatusSnapshot.unsupported(
        platform: 'web',
      );
    }

    if (defaultTargetPlatform !=
        TargetPlatform.android) {
      return DeviceStatusSnapshot.unsupported(
        platform:
            defaultTargetPlatform.name,
      );
    }

    try {
      final Map<dynamic, dynamic>?
          result =
          await _channel.invokeMethod<
              Map<dynamic, dynamic>>(
        'getDeviceStatus',
      );

      if (result == null) {
        return DeviceStatusSnapshot
            .unsupported(
          platform: 'android',
        );
      }

      return DeviceStatusSnapshot.fromMap(
        result,
      );
    } on PlatformException catch (error) {
      debugPrint(
        'DeviceStatusService indisponible : '
        '${error.code} ${error.message}',
      );

      return DeviceStatusSnapshot.unsupported(
        platform: 'android',
      );
    } catch (error) {
      debugPrint(
        'Erreur DeviceStatusService : $error',
      );

      return DeviceStatusSnapshot.unsupported(
        platform: 'android',
      );
    }
  }
}
