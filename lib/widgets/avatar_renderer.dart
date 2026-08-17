import 'dart:io';

import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../screens/avatar/avatar_assets.dart';

class AvatarRenderer extends StatelessWidget {
  final AvatarModel avatar;
  final double size;
  final bool showFrame;

  /// Pour les mini-avatars (Compagnie / demandes), évite le masque de tête ovale
  /// et utilise un recadrage rectangulaire transparent.
  ///
  /// Le rendu normal du Profil reste inchangé.
  final bool compactHeadCrop;

  const AvatarRenderer({
    super.key,
    required this.avatar,
    this.size = 260,
    this.showFrame = true,
    this.compactHeadCrop = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content;

    if (avatar.creationMode == AvatarCreationMode.photo &&
        avatar.generatedImagePath != null &&
        avatar.generatedImagePath!.isNotEmpty) {
      content = Image.file(
        File(avatar.generatedImagePath!),
        fit: BoxFit.contain,
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return _buildManualAvatar();
        },
      );
    } else {
      content = _buildManualAvatar();
    }

    if (!showFrame) {
      return SizedBox(
        width: size,
        height: size * 1.5,
        child: content,
      );
    }

    return Container(
      width: size,
      height: size * 1.5,
      decoration: BoxDecoration(
        color: const Color(0xff160e09),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xffffc857),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: content,
      ),
    );
  }

  Widget _buildManualAvatar() {
    final AvatarOutfitSpec outfit =
        AvatarAssets.outfit(avatar.outfit);

    final AvatarLayerSpec hair =
        AvatarAssets.hair(avatar.hair);

    final AvatarLayerSpec beard =
        AvatarAssets.beard(avatar.beard);

    final AvatarLayerSpec glasses =
        AvatarAssets.glasses(avatar.glasses);

    final AvatarLayerSpec? accessory =
        AvatarAssets.accessory(avatar.accessory);

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final double canvasWidth =
            constraints.maxWidth;

        final double canvasHeight =
            constraints.maxHeight;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // ================================================================
            // 1. TÊTE / COU UNIQUEMENT
            //
            // Les tenues de ton ZIP sont déjà des personnages habillés
            // presque complets. Si on affiche le corps entier derrière,
            // les anciens bras et jambes ressortent sur les côtés.
            //
            // On ne conserve donc que la tête et le cou du body_xx.
            // ================================================================

            if (compactHeadCrop)
              ClipRect(
                clipper:
                    const _AvatarHeadRectClipper(),
                child: Image.asset(
                  AvatarAssets.skin(
                    avatar.skin,
                  ),
                  fit: BoxFit.fill,
                  filterQuality:
                      FilterQuality.high,
                  errorBuilder: (
                    context,
                    error,
                    stackTrace,
                  ) {
                    return const SizedBox.shrink();
                  },
                ),
              )
            else
              ClipPath(
                clipper:
                    const _AvatarHeadClipper(),
                child: Image.asset(
                  AvatarAssets.skin(
                    avatar.skin,
                  ),
                  fit: BoxFit.fill,
                  filterQuality:
                      FilterQuality.high,
                  errorBuilder: (
                    context,
                    error,
                    stackTrace,
                  ) {
                    return const SizedBox.shrink();
                  },
                ),
              ),

            // ================================================================
            // 2. TENUE RECALÉE
            // ================================================================

            _positionedOutfit(
              spec: outfit,
              canvasWidth: canvasWidth,
              canvasHeight: canvasHeight,
            ),

            // ================================================================
            // 3. CHEVEUX
            // ================================================================

              _positionedSquareLayer(
                spec: hair,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
              ),

            // ================================================================
            // 4. BARBE
            // ================================================================

              _positionedSquareLayer(
                spec: beard,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
              ),

            // ================================================================
            // 5. LUNETTES
            // ================================================================

              _positionedSquareLayer(
                spec: glasses,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
              ),

            // ================================================================
            // 6. ACCESSOIRE
            // ================================================================

            if (accessory != null)
              _positionedSquareLayer(
                spec: accessory,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
              ),
          ],
        );
      },
    );
  }

  Widget _positionedOutfit({
    required AvatarOutfitSpec spec,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    return Positioned(
      left: canvasWidth * spec.left,
      top: canvasHeight * spec.top,
      width: canvasWidth * spec.width,
      height: canvasHeight * spec.height,
      child: Image.asset(
        spec.path,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _positionedSquareLayer({
    required AvatarLayerSpec spec,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    final double layerSize =
        canvasWidth * spec.width;

    return Positioned(
      left: canvasWidth * spec.left,
      top: canvasHeight * spec.top,
      width: layerSize,
      height: layerSize,
      child: Image.asset(
        spec.path,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return const SizedBox.shrink();
        },
      ),
    );
  }
}


// ============================================================================
// RECADRAGE TÊTE + COU POUR MINI-AVATARS
//
// Contrairement à _AvatarHeadClipper, ce crop ne dessine PAS d'ovale.
// Les pixels transparents du PNG restent transparents.
// ============================================================================

class _AvatarHeadRectClipper
    extends CustomClipper<Rect> {
  const _AvatarHeadRectClipper();

  @override
  Rect getClip(
    Size size,
  ) {
    return Rect.fromLTRB(
      size.width * 0.275,
      size.height * 0.020,
      size.width * 0.720,
      size.height * 0.390,
    );
  }

  @override
  bool shouldReclip(
    covariant CustomClipper<Rect> oldClipper,
  ) {
    return false;
  }
}

// ============================================================================
// MASQUE TÊTE + COU
// ============================================================================

class _AvatarHeadClipper
    extends CustomClipper<Path> {
  const _AvatarHeadClipper();

  @override
  Path getClip(
    Size size,
  ) {
    // Mesuré à partir de ton vrai gabarit 1024 x 1536.
    final Rect head = Rect.fromLTRB(
      size.width * 0.293,
      size.height * 0.029,
      size.width * 0.700,
      size.height * 0.300,
    );

    final Rect neck = Rect.fromLTRB(
      size.width * 0.435,
      size.height * 0.255,
      size.width * 0.610,
      size.height * 0.385,
    );

    final Path headPath = Path()
      ..addOval(
        head,
      );

    final Path neckPath = Path()
      ..addRect(
        neck,
      );

    return Path.combine(
      PathOperation.union,
      headPath,
      neckPath,
    );
  }

  @override
  bool shouldReclip(
    covariant CustomClipper<Path> oldClipper,
  ) {
    return false;
  }
}
