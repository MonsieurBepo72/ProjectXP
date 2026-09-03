import 'dart:async';

import 'package:flutter/material.dart';

import '../services/steam_sync_service.dart';

/// Bandeau global discret de synchronisation gaming.
///
/// Il vit au-dessus du Navigator : changer de page n'efface donc jamais
/// l'information. Une synchro en cours reste visible ; le résultat final
/// disparaît automatiquement après quelques secondes.
class GlobalGamingSyncStatus extends StatefulWidget {
  const GlobalGamingSyncStatus({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<GlobalGamingSyncStatus> createState() =>
      _GlobalGamingSyncStatusState();
}

class _GlobalGamingSyncStatusState
    extends State<GlobalGamingSyncStatus> {
  SteamSyncUiState _state =
      SteamSyncService.syncState.value;

  Timer? _hideTimer;
  bool _showTerminalState = false;

  @override
  void initState() {
    super.initState();

    SteamSyncService.syncState.addListener(
      _handleSyncState,
    );

    _handleSyncState();
  }

  @override
  void dispose() {
    SteamSyncService.syncState.removeListener(
      _handleSyncState,
    );
    _hideTimer?.cancel();
    super.dispose();
  }

  void _handleSyncState() {
    if (!mounted) {
      return;
    }

    final SteamSyncUiState next =
        SteamSyncService.syncState.value;

    _hideTimer?.cancel();

    setState(() {
      _state = next;
      _showTerminalState =
          next.phase == SteamSyncPhase.completed ||
              next.phase == SteamSyncPhase.failed;
    });

    if (_showTerminalState) {
      _hideTimer = Timer(
        const Duration(seconds: 5),
        () {
          if (!mounted) {
            return;
          }

          setState(() {
            _showTerminalState = false;
          });
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool visible =
        _state.running || _showTerminalState;

    return Stack(
      children: [
        widget.child,
        if (visible)
          Positioned(
            left: 14,
            right: 14,
            bottom: 18,
            child: SafeArea(
              top: false,
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(
                    milliseconds: 220,
                  ),
                  child: _SyncBanner(
                    key: ValueKey<String>(
                      '${_state.phase.name}-'
                      '${_state.current}-'
                      '${_state.total}-'
                      '${_state.label}',
                    ),
                    state: _state,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({
    super.key,
    required this.state,
  });

  final SteamSyncUiState state;

  @override
  Widget build(BuildContext context) {
    final bool failed =
        state.phase == SteamSyncPhase.failed;

    final bool completed =
        state.phase == SteamSyncPhase.completed;

    final IconData icon = failed
        ? Icons.error_outline_rounded
        : completed
            ? Icons.check_circle_outline_rounded
            : Icons.sync_rounded;

    final Color accent = failed
        ? Colors.redAccent
        : completed
            ? const Color(0xff69d39b)
            : const Color(0xffffc857);

    return Material(
      color: const Color(0xf2222529),
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            if (state.running)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: accent,
                  value: state.total > 0
                      ? (state.current / state.total)
                          .clamp(0.0, 1.0)
                      : null,
                ),
              )
            else
              Icon(
                icon,
                color: accent,
                size: 22,
              ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                state.message?.trim().isNotEmpty == true
                    ? state.message!.trim()
                    : state.label,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
