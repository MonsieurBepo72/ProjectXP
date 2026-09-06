import 'dart:async';

import 'package:flutter/material.dart';

import '../services/gaming_sync_service.dart';
import '../services/steam_sync_service.dart';

/// État Steam affiché uniquement dans la Bibliothèque.
///
/// - pendant la synchro : barre continue vert / rouge / gris ;
/// - après la synchro : bloc persistant des jeux réellement "à revoir" ;
/// - le bouton de reprise ne relance que ces jeux en erreur.
class SteamLibrarySyncProgress extends StatelessWidget {
  const SteamLibrarySyncProgress({
    super.key,
    required this.fallbackLabel,
  });

  final String fallbackLabel;

  static const Color successColor = Color(0xff8fd5a6);
  static const Color errorColor = Color(0xffff5c6c);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GamingSyncUiState>(
      valueListenable: GamingSyncService.syncState,
      builder: (context, gamingState, child) {
        if (gamingState.running) {
          return _RunningGamingSync(
            state: gamingState,
            fallbackLabel: fallbackLabel,
          );
        }

        return ValueListenableBuilder<SteamSyncUiState>(
          valueListenable: SteamSyncService.syncState,
          builder: (context, steamState, child) {
            if (steamState.running) {
              return _RunningSteamSync(
                state: steamState,
                fallbackLabel: fallbackLabel,
              );
            }

            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

class _RunningGamingSync extends StatelessWidget {
  const _RunningGamingSync({
    required this.state,
    required this.fallbackLabel,
  });

  final GamingSyncUiState state;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final int issueCount = state.outcomes
        .where((outcome) => outcome == GamingSyncItemOutcome.failed)
        .length;
    final String label = state.label.trim().isNotEmpty
        ? state.label.trim()
        : fallbackLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        _GamingSyncHistoryBar(state: state),
        if (state.total > 0) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${state.current} / ${state.total} traités',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (issueCount > 0)
                Text(
                  '$issueCount à revoir',
                  style: const TextStyle(
                    color: SteamLibrarySyncProgress.errorColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RunningSteamSync extends StatelessWidget {
  const _RunningSteamSync({
    required this.state,
    required this.fallbackLabel,
  });

  final SteamSyncUiState state;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final int issueCount = state.outcomes
        .where((outcome) => outcome == SteamSyncGameOutcome.failed)
        .length;

    final String label = state.label.trim().isNotEmpty
        ? state.label.trim()
        : fallbackLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        _SteamSyncHistoryBar(state: state),
        if (state.total > 0) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${state.current} / ${state.total} vérifiés',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (issueCount > 0)
                Text(
                  '$issueCount à revoir',
                  style: const TextStyle(
                    color: SteamLibrarySyncProgress.errorColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class SteamLibraryIssuesFloatingButton extends StatefulWidget {
  const SteamLibraryIssuesFloatingButton({
    super.key,
  });

  @override
  State<SteamLibraryIssuesFloatingButton> createState() =>
      _SteamLibraryIssuesFloatingButtonState();
}

class _SteamLibraryIssuesFloatingButtonState
    extends State<SteamLibraryIssuesFloatingButton> {
  List<SteamAchievementSyncIssue> _savedIssues =
      const <SteamAchievementSyncIssue>[];
  int _retryAttempts = 0;

  @override
  void initState() {
    super.initState();
    SteamSyncService.syncState.addListener(_handleSyncState);
    unawaited(_loadSavedState());
  }

  @override
  void dispose() {
    SteamSyncService.syncState.removeListener(_handleSyncState);
    super.dispose();
  }

  void _handleSyncState() {
    if (!mounted) {
      return;
    }

    final SteamSyncUiState state = SteamSyncService.syncState.value;
    if (state.phase != SteamSyncPhase.completed) {
      return;
    }

    setState(() {
      _savedIssues = state.issues;
    });
    unawaited(_loadRetryAttempts());
  }

  Future<void> _loadRetryAttempts() async {
    final int attempts = await SteamSyncService.loadIssueRetryAttempts();
    if (!mounted) {
      return;
    }

    setState(() {
      _retryAttempts = attempts;
    });
  }

  Future<void> _loadSavedState() async {
    final List<SteamAchievementSyncIssue> issues =
        await SteamSyncService.loadSavedIssues();
    final int attempts = await SteamSyncService.loadIssueRetryAttempts();

    if (!mounted) {
      return;
    }

    setState(() {
      _savedIssues = issues;
      _retryAttempts = attempts;
    });
  }

  Future<void> _retryIssues() async {
    final int persisted = await SteamSyncService.loadIssueRetryAttempts();
    if (!mounted ||
        persisted >= SteamSyncService.maxIssueRetryAttempts) {
      return;
    }

    setState(() {
      _retryAttempts = (persisted + 1)
          .clamp(0, SteamSyncService.maxIssueRetryAttempts)
          .toInt();
    });

    await SteamSyncService.retryFailedAchievements();
    await _loadSavedState();
  }

  Future<void> _openIssues(
    List<SteamAchievementSyncIssue> issues,
  ) async {
    if (issues.isEmpty || !mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff211719),
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final int count = issues.length;
        final int nextAttempt = (_retryAttempts + 1)
            .clamp(1, SteamSyncService.maxIssueRetryAttempts)
            .toInt();

        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: SteamLibrarySyncProgress.errorColor,
                        size: 22,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          count == 1
                              ? '1 JEU À REVOIR'
                              : '$count JEUX À REVOIR',
                          style: const TextStyle(
                            color: SteamLibrarySyncProgress.errorColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fermer',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    count == 1
                        ? 'Steam n’a pas pu terminer la synchronisation de ce jeu.'
                        : 'Steam n’a pas pu terminer la synchronisation de ces jeux.',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final SteamAchievementSyncIssue issue in issues)
                          _SteamIssueRow(issue: issue),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nouvelle tentative $nextAttempt/'
                    '${SteamSyncService.maxIssueRetryAttempts}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        unawaited(_retryIssues());
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            SteamLibrarySyncProgress.errorColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        count == 1
                            ? 'RÉESSAYER CE JEU'
                            : 'RÉESSAYER LES ÉCHECS',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GamingSyncUiState>(
      valueListenable: GamingSyncService.syncState,
      builder: (context, gamingState, child) {
        if (gamingState.running) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<SteamSyncUiState>(
          valueListenable: SteamSyncService.syncState,
          builder: (context, steamState, child) {
            if (steamState.running) {
              return const SizedBox.shrink();
            }

            if (steamState.phase == SteamSyncPhase.completed &&
                steamState.issues.isEmpty) {
              return const SizedBox.shrink();
            }

            final List<SteamAchievementSyncIssue> visibleIssues =
                steamState.issues.isNotEmpty
                ? steamState.issues
                : _savedIssues;

            if (visibleIssues.isEmpty ||
                _retryAttempts >= SteamSyncService.maxIssueRetryAttempts) {
              return const SizedBox.shrink();
            }

            final int count = visibleIssues.length;

            return Tooltip(
              message: count == 1
                  ? '1 jeu à revoir'
                  : '$count jeux à revoir',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    unawaited(_openIssues(visibleIssues));
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SteamLibrarySyncProgress.errorColor,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.38),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Center(
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 27,
                          ),
                        ),
                        Positioned(
                          top: -5,
                          right: -5,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 23,
                              minHeight: 23,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff8f1723),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SteamIssueRow extends StatelessWidget {
  const _SteamIssueRow({required this.issue});

  final SteamAchievementSyncIssue issue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xff1a1517),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline_rounded,
              color: SteamLibrarySyncProgress.errorColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title.trim().isEmpty ? 'Jeu Steam' : issue.title.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _friendlyReason(issue.message),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _friendlyReason(String raw) {
    final String clean = raw.trim();
    final String lower = clean.toLowerCase();

    if (lower.contains('429') ||
        lower.contains('rate limit') ||
        lower.contains('too many')) {
      return 'Steam limite temporairement les requêtes. Réessaie dans un moment.';
    }

    if (lower.contains('private') ||
        lower.contains('privacy') ||
        lower.contains('403')) {
      return 'Les statistiques Steam de ce jeu ne sont pas accessibles.';
    }

    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Steam n’a pas répondu à temps.';
    }

    if (lower.contains('http 500') ||
        lower.contains('internal server error')) {
      return 'Steam a rencontré une erreur interne temporaire pour ce jeu. Réessaie plus tard.';
    }

    if (lower.contains('http 502') ||
        lower.contains('http 503') ||
        lower.contains('http 504')) {
      return 'Les serveurs Steam sont temporairement indisponibles pour ce jeu. Réessaie plus tard.';
    }

    if (lower.contains('steam http 5')) {
      return 'Steam a rencontré un problème serveur temporaire pour ce jeu. Réessaie plus tard.';
    }

    if (lower.contains('réponse steam invalide') ||
        lower.contains('invalid response')) {
      return 'Steam a renvoyé une réponse invalide.';
    }

    if (clean.isEmpty) {
      return 'La synchronisation Steam de ce jeu n’a pas abouti.';
    }

    return clean;
  }
}

class _GamingSyncHistoryBar extends StatelessWidget {
  const _GamingSyncHistoryBar({required this.state});

  final GamingSyncUiState state;

  @override
  Widget build(BuildContext context) {
    if (state.total <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: const LinearProgressIndicator(
          minHeight: 7,
          color: SteamLibrarySyncProgress.successColor,
          backgroundColor: Color(0xff343940),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 8,
      child: CustomPaint(
        painter: _GamingSyncHistoryPainter(
          total: state.total,
          outcomes: state.outcomes,
        ),
      ),
    );
  }
}

class _GamingSyncHistoryPainter extends CustomPainter {
  const _GamingSyncHistoryPainter({
    required this.total,
    required this.outcomes,
  });

  final int total;
  final List<GamingSyncItemOutcome> outcomes;

  static const Color _successColor = SteamLibrarySyncProgress.successColor;
  static const Color _errorColor = SteamLibrarySyncProgress.errorColor;
  static const Color _pendingColor = Color(0xff343940);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || total <= 0) {
      return;
    }

    final RRect clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );

    canvas.save();
    canvas.clipRRect(clip);
    canvas.drawRect(Offset.zero & size, Paint()..color = _pendingColor);

    final int processed = outcomes.length.clamp(0, total).toInt();
    if (processed == 0) {
      canvas.restore();
      return;
    }

    final double segmentWidth = size.width / total;
    int runStart = 0;
    GamingSyncItemOutcome runOutcome = outcomes.first;

    for (int index = 1; index <= processed; index += 1) {
      final bool endOfRun =
          index == processed || outcomes[index] != runOutcome;
      if (!endOfRun) {
        continue;
      }

      final double left = runStart * segmentWidth;
      final double right = index * segmentWidth;
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = _colorFor(runOutcome),
      );

      if (index < processed) {
        final GamingSyncItemOutcome nextOutcome = outcomes[index];
        final double boundary = index * segmentWidth;
        final double fadeWidth =
            (segmentWidth * 0.8).clamp(1.0, 6.0).toDouble();
        final Rect fadeRect = Rect.fromLTRB(
          boundary - (fadeWidth / 2),
          0,
          boundary + (fadeWidth / 2),
          size.height,
        );

        canvas.drawRect(
          fadeRect,
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                _colorFor(runOutcome),
                _colorFor(nextOutcome),
              ],
            ).createShader(fadeRect),
        );

        runStart = index;
        runOutcome = nextOutcome;
      }
    }

    final double processedRight = processed * segmentWidth;
    if (processed < total && processedRight > 0) {
      final double fadeWidth =
          (segmentWidth * 0.7).clamp(1.0, 5.0).toDouble();
      final Rect fadeRect = Rect.fromLTRB(
        (processedRight - fadeWidth).clamp(0.0, size.width).toDouble(),
        0,
        processedRight.clamp(0.0, size.width).toDouble(),
        size.height,
      );

      if (fadeRect.width > 0) {
        canvas.drawRect(
          fadeRect,
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                _colorFor(outcomes[processed - 1]),
                _pendingColor,
              ],
            ).createShader(fadeRect),
        );
      }
    }

    canvas.drawRRect(
      clip,
      Paint()
        ..color = const Color(0x33ffffff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  static Color _colorFor(GamingSyncItemOutcome outcome) {
    switch (outcome) {
      case GamingSyncItemOutcome.success:
        return _successColor;
      case GamingSyncItemOutcome.failed:
        return _errorColor;
    }
  }

  @override
  bool shouldRepaint(covariant _GamingSyncHistoryPainter oldDelegate) {
    if (oldDelegate.total != total ||
        oldDelegate.outcomes.length != outcomes.length) {
      return true;
    }

    for (int index = 0; index < outcomes.length; index += 1) {
      if (oldDelegate.outcomes[index] != outcomes[index]) {
        return true;
      }
    }

    return false;
  }
}

class _SteamSyncHistoryBar extends StatelessWidget {
  const _SteamSyncHistoryBar({required this.state});

  final SteamSyncUiState state;

  @override
  Widget build(BuildContext context) {
    if (state.total <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: const LinearProgressIndicator(
          minHeight: 7,
          color: SteamLibrarySyncProgress.successColor,
          backgroundColor: Color(0xff343940),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 8,
      child: CustomPaint(
        painter: _SteamSyncHistoryPainter(
          total: state.total,
          outcomes: state.outcomes,
        ),
      ),
    );
  }
}

class _SteamSyncHistoryPainter extends CustomPainter {
  const _SteamSyncHistoryPainter({
    required this.total,
    required this.outcomes,
  });

  final int total;
  final List<SteamSyncGameOutcome> outcomes;

  static const Color _successColor = SteamLibrarySyncProgress.successColor;
  static const Color _errorColor = SteamLibrarySyncProgress.errorColor;
  static const Color _pendingColor = Color(0xff343940);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || total <= 0) {
      return;
    }

    final RRect clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );

    canvas.save();
    canvas.clipRRect(clip);

    canvas.drawRect(Offset.zero & size, Paint()..color = _pendingColor);

    final int processed = outcomes.length.clamp(0, total).toInt();
    if (processed == 0) {
      canvas.restore();
      return;
    }

    final double segmentWidth = size.width / total;

    int runStart = 0;
    SteamSyncGameOutcome runOutcome = outcomes.first;

    for (int index = 1; index <= processed; index += 1) {
      final bool endOfRun =
          index == processed || outcomes[index] != runOutcome;

      if (!endOfRun) {
        continue;
      }

      final double left = runStart * segmentWidth;
      final double right = index * segmentWidth;

      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = _colorFor(runOutcome),
      );

      if (index < processed) {
        final SteamSyncGameOutcome nextOutcome = outcomes[index];
        final double boundary = index * segmentWidth;
        final double fadeWidth = (segmentWidth * 0.8).clamp(1.0, 6.0).toDouble();
        final Rect fadeRect = Rect.fromLTRB(
          boundary - (fadeWidth / 2),
          0,
          boundary + (fadeWidth / 2),
          size.height,
        );

        canvas.drawRect(
          fadeRect,
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                _colorFor(runOutcome),
                _colorFor(nextOutcome),
              ],
            ).createShader(fadeRect),
        );

        runStart = index;
        runOutcome = nextOutcome;
      }
    }

    final double processedRight = processed * segmentWidth;
    if (processed < total && processedRight > 0) {
      final double fadeWidth = (segmentWidth * 0.7).clamp(1.0, 5.0).toDouble();
      final Rect fadeRect = Rect.fromLTRB(
        (processedRight - fadeWidth).clamp(0.0, size.width).toDouble(),
        0,
        processedRight.clamp(0.0, size.width).toDouble(),
        size.height,
      );

      if (fadeRect.width > 0) {
        canvas.drawRect(
          fadeRect,
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                _colorFor(outcomes[processed - 1]),
                _pendingColor,
              ],
            ).createShader(fadeRect),
        );
      }
    }

    canvas.drawRRect(
      clip,
      Paint()
        ..color = const Color(0x33ffffff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    canvas.restore();
  }

  static Color _colorFor(SteamSyncGameOutcome outcome) {
    switch (outcome) {
      case SteamSyncGameOutcome.success:
        return _successColor;
      case SteamSyncGameOutcome.failed:
        return _errorColor;
    }
  }

  @override
  bool shouldRepaint(covariant _SteamSyncHistoryPainter oldDelegate) {
    if (oldDelegate.total != total ||
        oldDelegate.outcomes.length != outcomes.length) {
      return true;
    }

    for (int index = 0; index < outcomes.length; index += 1) {
      if (oldDelegate.outcomes[index] != outcomes[index]) {
        return true;
      }
    }

    return false;
  }
}
