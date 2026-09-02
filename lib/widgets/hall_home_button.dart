import 'package:flutter/material.dart';

/// Bouton de navigation réservé aux grands espaces directement ouverts
/// depuis le Hall de Project XP.
///
/// Convention :
/// - maison / cottage = retour au Hall ;
/// - flèche = retour interne vers l'écran parent d'une sous-app.
class HallHomeButton extends StatelessWidget {
  const HallHomeButton({
    super.key,
    this.onPressed,
    this.width = 44,
    this.height = 42,
    this.iconSize = 23,
    this.margin = EdgeInsets.zero,
  });

  final Future<void> Function()? onPressed;
  final double width;
  final double height;
  final double iconSize;
  final EdgeInsetsGeometry margin;

  Future<void> _handleTap(BuildContext context) async {
    final Future<void> Function()? callback = onPressed;

    if (callback != null) {
      await callback();
      return;
    }

    await Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Tooltip(
        message: 'Retour au Hall',
        child: Semantics(
          button: true,
          label: 'Retour au Hall',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _handleTap(context);
              },
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: width,
                height: height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xf21a100b),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: const Color(0xffb67a34),
                    width: 1.35,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                    BoxShadow(
                      color: Color(0x339e642b),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.cottage_rounded,
                  size: iconSize,
                  color: const Color(0xffffd27a),
                  shadows: const [
                    Shadow(
                      color: Color(0xaa000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
