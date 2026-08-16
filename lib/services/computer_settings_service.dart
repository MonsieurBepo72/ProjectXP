import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ComputerSettings {
  final bool musicEnabled;
  final bool soundEffectsEnabled;
  final bool vibrationEnabled;
  final bool notificationsEnabled;
  final bool reducedAnimations;
  final bool confirmationsEnabled;
  final bool bjornTipsEnabled;

  const ComputerSettings({
    required this.musicEnabled,
    required this.soundEffectsEnabled,
    required this.vibrationEnabled,
    required this.notificationsEnabled,
    required this.reducedAnimations,
    required this.confirmationsEnabled,
    required this.bjornTipsEnabled,
  });

  factory ComputerSettings.defaults() {
    return const ComputerSettings(
      musicEnabled: true,
      soundEffectsEnabled: true,
      vibrationEnabled: true,
      notificationsEnabled: true,
      reducedAnimations: false,
      confirmationsEnabled: true,
      bjornTipsEnabled: true,
    );
  }

  ComputerSettings copyWith({
    bool? musicEnabled,
    bool? soundEffectsEnabled,
    bool? vibrationEnabled,
    bool? notificationsEnabled,
    bool? reducedAnimations,
    bool? confirmationsEnabled,
    bool? bjornTipsEnabled,
  }) {
    return ComputerSettings(
      musicEnabled:
          musicEnabled ?? this.musicEnabled,
      soundEffectsEnabled:
          soundEffectsEnabled ?? this.soundEffectsEnabled,
      vibrationEnabled:
          vibrationEnabled ?? this.vibrationEnabled,
      notificationsEnabled:
          notificationsEnabled ?? this.notificationsEnabled,
      reducedAnimations:
          reducedAnimations ?? this.reducedAnimations,
      confirmationsEnabled:
          confirmationsEnabled ?? this.confirmationsEnabled,
      bjornTipsEnabled:
          bjornTipsEnabled ?? this.bjornTipsEnabled,
    );
  }
}

class ComputerSettingsService {
  static const String _musicKey =
      'project_xp_settings_music';
  static const String _soundEffectsKey =
      'project_xp_settings_sound_effects';
  static const String _vibrationKey =
      'project_xp_settings_vibration';
  static const String _notificationsKey =
      'project_xp_settings_notifications';
  static const String _reducedAnimationsKey =
      'project_xp_settings_reduced_animations';
  static const String _confirmationsKey =
      'project_xp_settings_confirmations';
  static const String _bjornTipsKey =
      'project_xp_settings_bjorn_tips';

  static bool _initialized = false;

  static final ValueNotifier<ComputerSettings>
      settingsNotifier =
      ValueNotifier<ComputerSettings>(
    ComputerSettings.defaults(),
  );

  static ComputerSettings get current =>
      settingsNotifier.value;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final ComputerSettings defaults =
        ComputerSettings.defaults();

    settingsNotifier.value =
        ComputerSettings(
      musicEnabled:
          prefs.getBool(_musicKey) ??
              defaults.musicEnabled,
      soundEffectsEnabled:
          prefs.getBool(_soundEffectsKey) ??
              defaults.soundEffectsEnabled,
      vibrationEnabled:
          prefs.getBool(_vibrationKey) ??
              defaults.vibrationEnabled,
      notificationsEnabled:
          prefs.getBool(_notificationsKey) ??
              defaults.notificationsEnabled,
      reducedAnimations:
          prefs.getBool(
                _reducedAnimationsKey,
              ) ??
              defaults.reducedAnimations,
      confirmationsEnabled:
          prefs.getBool(
                _confirmationsKey,
              ) ??
              defaults.confirmationsEnabled,
      bjornTipsEnabled:
          prefs.getBool(_bjornTipsKey) ??
              defaults.bjornTipsEnabled,
    );

    _initialized = true;
  }

  static Future<ComputerSettings> load() async {
    if (!_initialized) {
      await initialize();
    }

    return current;
  }

  static Future<void> save(
    ComputerSettings settings,
  ) async {
    if (!_initialized) {
      await initialize();
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await Future.wait<bool>([
      prefs.setBool(
        _musicKey,
        settings.musicEnabled,
      ),
      prefs.setBool(
        _soundEffectsKey,
        settings.soundEffectsEnabled,
      ),
      prefs.setBool(
        _vibrationKey,
        settings.vibrationEnabled,
      ),
      prefs.setBool(
        _notificationsKey,
        settings.notificationsEnabled,
      ),
      prefs.setBool(
        _reducedAnimationsKey,
        settings.reducedAnimations,
      ),
      prefs.setBool(
        _confirmationsKey,
        settings.confirmationsEnabled,
      ),
      prefs.setBool(
        _bjornTipsKey,
        settings.bjornTipsEnabled,
      ),
    ]);

    // IMPORTANT :
    // tout le reste de l'app peut maintenant écouter
    // ce ValueNotifier et réagir immédiatement.
    settingsNotifier.value = settings;
  }
}
