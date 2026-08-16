import 'package:flutter/material.dart';

import '../services/app_audio_service.dart';

class GlobalTapFeedback
    extends StatefulWidget {
  final Widget child;

  const GlobalTapFeedback({
    super.key,
    required this.child,
  });

  @override
  State<GlobalTapFeedback> createState() =>
      _GlobalTapFeedbackState();
}

class _GlobalTapFeedbackState
    extends State<GlobalTapFeedback> {
  final Map<int, Offset> _starts =
      <int, Offset>{};

  final Set<int> _moved =
      <int>{};

  static const double _moveTolerance = 18;

  void _onPointerDown(
    PointerDownEvent event,
  ) {
    _starts[event.pointer] =
        event.position;

    _moved.remove(event.pointer);
  }

  void _onPointerMove(
    PointerMoveEvent event,
  ) {
    final Offset? start =
        _starts[event.pointer];

    if (start == null) {
      return;
    }

    final double distance =
        (event.position - start)
            .distance;

    if (distance >
        _moveTolerance) {
      _moved.add(event.pointer);
    }
  }

  void _onPointerUp(
    PointerUpEvent event,
  ) {
    final bool wasTap =
        _starts.containsKey(
          event.pointer,
        ) &&
        !_moved.contains(
          event.pointer,
        );

    _starts.remove(
      event.pointer,
    );

    _moved.remove(
      event.pointer,
    );

    if (wasTap) {
      AppAudioService.instance
          .tapFeedback();
    }
  }

  void _onPointerCancel(
    PointerCancelEvent event,
  ) {
    _starts.remove(
      event.pointer,
    );

    _moved.remove(
      event.pointer,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Listener(
      behavior:
          HitTestBehavior.translucent,
      onPointerDown:
          _onPointerDown,
      onPointerMove:
          _onPointerMove,
      onPointerUp:
          _onPointerUp,
      onPointerCancel:
          _onPointerCancel,
      child: widget.child,
    );
  }
}
