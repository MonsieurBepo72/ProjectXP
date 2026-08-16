import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'computer_settings_service.dart';

class AppAudioService
    with WidgetsBindingObserver {
  AppAudioService._();

  static final AppAudioService instance =
      AppAudioService._();

  final AudioPlayer _musicPlayer =
      AudioPlayer();

  final AudioPlayer _effectPlayer =
      AudioPlayer();

  bool _initialized = false;
  bool _musicStarted = false;
  bool _appIsActive = true;

  static const String _musicAsset =
      'audio/music/project_xp_hall_loop.wav';

  static const String _clickAsset =
      'audio/sfx/ui_click.wav';

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    WidgetsBinding.instance.addObserver(this);

    await _musicPlayer.setReleaseMode(
      ReleaseMode.loop,
    );

    await _musicPlayer.setVolume(0.26);

    ComputerSettingsService.settingsNotifier
        .addListener(_settingsChanged);

    _initialized = true;

    await _syncMusic();
  }

  void _settingsChanged() {
    _syncMusic();
  }

  Future<void> _syncMusic() async {
    if (!_initialized) {
      return;
    }

    final bool shouldPlay =
        ComputerSettingsService
                .current.musicEnabled &&
            _appIsActive;

    if (shouldPlay) {
      if (_musicStarted) {
        await _musicPlayer.resume();
      } else {
        await _musicPlayer.play(
          AssetSource(_musicAsset),
        );

        _musicStarted = true;
      }

      return;
    }

    if (_musicStarted) {
      await _musicPlayer.pause();
    }
  }

  Future<void> playClick() async {
    if (!ComputerSettingsService
        .current.soundEffectsEnabled) {
      return;
    }

    try {
      await _effectPlayer.stop();

      await _effectPlayer.play(
        AssetSource(_clickAsset),
        volume: 0.55,
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {
      // Un son ne doit jamais bloquer l'application.
    }
  }

  Future<void> tapFeedback() async {
    final ComputerSettings settings =
        ComputerSettingsService.current;

    if (settings.vibrationEnabled) {
      await HapticFeedback.selectionClick();
    }

    if (settings.soundEffectsEnabled) {
      await playClick();
    }
  }

  Future<void> notificationFeedback() async {
    final ComputerSettings settings =
        ComputerSettingsService.current;

    if (!settings.notificationsEnabled) {
      return;
    }

    if (settings.vibrationEnabled) {
      await HapticFeedback.mediumImpact();
    }

    if (settings.soundEffectsEnabled) {
      try {
        await _effectPlayer.stop();

        await _effectPlayer.play(
          AssetSource(
            'audio/sfx/notification.wav',
          ),
          volume: 0.70,
          mode: PlayerMode.lowLatency,
        );
      } catch (_) {
        // Une erreur audio ne doit pas bloquer l'UI.
      }
    }
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    _appIsActive =
        state == AppLifecycleState.resumed;

    _syncMusic();
  }

  Future<void> dispose() async {
    if (!_initialized) {
      return;
    }

    WidgetsBinding.instance.removeObserver(
      this,
    );

    ComputerSettingsService.settingsNotifier
        .removeListener(_settingsChanged);

    await _musicPlayer.dispose();
    await _effectPlayer.dispose();

    _initialized = false;
  }
}
