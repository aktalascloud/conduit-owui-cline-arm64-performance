import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';

/// Camera gestures stay native; the isolated viewport receives numbers only.
class VoiceAvatarInteraction extends StatefulWidget {
  const VoiceAvatarInteraction({
    super.key,
    required this.child,
    required this.enabled,
    required this.onView,
  });
  final Widget child;
  final bool enabled;
  final ValueChanged<Map<String, Object>> onView;
  @override
  State<VoiceAvatarInteraction> createState() => _VoiceAvatarInteractionState();
}

class _VoiceAvatarInteractionState extends State<VoiceAvatarInteraction> {
  var _scale = 1.0;
  void _send(Map<String, Object> value) {
    if (widget.enabled &&
        value.values.every((v) => v is bool || (v is num && v.isFinite)))
      widget.onView(value);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && widget.enabled) {
              GestureBinding.instance.pointerSignalResolver.register(
                event,
                (_) => _send({
                  'scale': math.exp(
                    event.scrollDelta.dy.clamp(-240, 240) * .001,
                  ),
                }),
              );
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) => _scale = 1,
            onScaleUpdate: (event) {
              if (event.pointerCount > 1) {
                if (event.scale > 0)
                  _send({
                    'scale': _scale / event.scale,
                    'panX': event.focalPointDelta.dx / 2,
                    'panY': event.focalPointDelta.dy / 2,
                  });
              } else {
                _send({
                  'dx': event.focalPointDelta.dx,
                  'dy': event.focalPointDelta.dy,
                });
              }
              _scale = event.scale;
            },
            onDoubleTap: () => _send({'reset': true}),
            child: widget.child,
          ),
        ),
        Positioned(
          top: Spacing.sm,
          right: Spacing.sm,
          child: Material(
            color: context.conduitTheme.cardBackground.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(AppBorderRadius.button),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('avatar-reset-view'),
                  tooltip: l.voiceAvatarResetView,
                  onPressed: widget.enabled
                      ? () => _send({'reset': true})
                      : null,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
