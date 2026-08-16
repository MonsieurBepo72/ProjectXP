import '../../models/avatar_model.dart';

class AvatarLayerSpec {
  final String path;

  // Position / taille relatives au canevas 1024 x 1536.
  final double left;
  final double top;
  final double width;

  const AvatarLayerSpec({
    required this.path,
    required this.left,
    required this.top,
    required this.width,
  });
}

class AvatarOutfitSpec {
  final String path;

  // Les tenues sont elles aussi en 1024 x 1536,
  // mais le personnage dessiné dedans est plus grand que le gabarit de base.
  // On les réduit et on les descend légèrement.
  final double left;
  final double top;
  final double width;
  final double height;

  const AvatarOutfitSpec({
    required this.path,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class AvatarAssets {
  static const String _root =
      'assets/images/avatars/male';

  // ==========================================================================
  // BASE
  // ==========================================================================

  static String skin(
    AvatarSkin skin,
  ) {
    switch (skin) {
      case AvatarSkin.body01:
        return '$_root/base/body_01.png';

      case AvatarSkin.body02:
        return '$_root/base/body_02.png';

      case AvatarSkin.body03:
        return '$_root/base/body_03.png';

      case AvatarSkin.body04:
        return '$_root/base/body_04.png';
    }
  }

  // ==========================================================================
  // TENUES
  // ==========================================================================

  static AvatarOutfitSpec outfit(
    AvatarOutfit outfit,
  ) {
    switch (outfit) {
      // Aventurier
      case AvatarOutfit.outfit01:
        return const AvatarOutfitSpec(
          path: '$_root/outfit/outfit_01.png',
          left: 0.040,
          top: 0.070,
          width: 0.920,
          height: 0.920,
        );

      // Mage
      case AvatarOutfit.outfit02:
        return const AvatarOutfitSpec(
          path: '$_root/outfit/outfit_02.png',
          left: 0.040,
          top: 0.065,
          width: 0.920,
          height: 0.920,
        );

      // Rôdeur
      case AvatarOutfit.outfit03:
        return const AvatarOutfitSpec(
          path: '$_root/outfit/outfit_03.png',
          left: 0.040,
          top: 0.070,
          width: 0.920,
          height: 0.920,
        );

      // Tavernier
      case AvatarOutfit.outfit04:
        return const AvatarOutfitSpec(
          path: '$_root/outfit/outfit_04.png',
          left: 0.045,
          top: 0.070,
          width: 0.910,
          height: 0.910,
        );
    }
  }

  // ==========================================================================
  // CHEVEUX
  // ==========================================================================

  static AvatarLayerSpec hair(
  AvatarHair hair,
) {
  switch (hair) {
    case AvatarHair.none:
      return const AvatarLayerSpec(
        path: '$_root/hair/none.png',
        left: 0,
        top: 0,
        width: 1,
      );

    // Ébouriffé
    case AvatarHair.hair02:
      return const AvatarLayerSpec(
        path: '$_root/hair/hair_02.png',
        left: -0.14,
        top: -0.01,
        width: 1.25,
      );

    // Balayé
    case AvatarHair.hair03:
      return const AvatarLayerSpec(
        path: '$_root/hair/hair_03.png',
        left: -0.01,
        top: -0.015,
        width: 1,
      );

    // Volumineux
    case AvatarHair.hair04:
      return const AvatarLayerSpec(
        path: '$_root/hair/hair_04.png',
        left: -0.16,
        top: 0,
        width: 1.30,
      );

    // Ondulé
    case AvatarHair.hair05:
      return const AvatarLayerSpec(
        path: '$_root/hair/hair_05.png',
        left: -0.18,
        top: -0.005,
        width: 1.35,
      );

    // Mi-long
    case AvatarHair.hair06:
      return const AvatarLayerSpec(
        path: '$_root/hair/hair_06.png',
        left: -0.241,
        top: -0.013,
        width: 1.48,
      );
  }
}

  // ==========================================================================
  // BARBES
  // ==========================================================================

  static AvatarLayerSpec beard(
  AvatarBeard beard,
) {
  switch (beard) {
    case AvatarBeard.none:
      return const AvatarLayerSpec(
        path: '$_root/beard/none.png',
        left: 0,
        top: 0,
        width: 1,
      );

    // Courte
    case AvatarBeard.beard02:
      return const AvatarLayerSpec(
        path: '$_root/beard/beard_02.png',
        left: 0.07,
        top: -0.035,
        width: 0.90,
      );

    // Fournie
    case AvatarBeard.beard03:
      return const AvatarLayerSpec(
        path: '$_root/beard/beard_03.png',
        left: 0.22,
        top: 0.085,
        width: 0.6,
      );

    // Nordique
    case AvatarBeard.beard04:
      return const AvatarLayerSpec(
        path: '$_root/beard/beard_04.png',
        left: 0.12,
        top: 0.062,
        width: 0.8,
      );

    // Bouc
    case AvatarBeard.beard05:
      return const AvatarLayerSpec(
        path: '$_root/beard/beard_05.png',
        left: 0.01,
        top: -0.05,
        width: 1,
      );
  }
}

  // ==========================================================================
  // LUNETTES
  // ==========================================================================

  static AvatarLayerSpec glasses(
  AvatarGlasses glasses,
) {
  switch (glasses) {
    case AvatarGlasses.none:
      return const AvatarLayerSpec(
        path: '$_root/glasses/none.png',
        left: 0,
        top: 0,
        width: 1,
      );

    // Rondes
    case AvatarGlasses.glasses01:
      return const AvatarLayerSpec(
        path: '$_root/glasses/glasses_01.png',
        left: 0.2,
        top: 0.102,
        width: 0.6,
      );

    // Carrées
    case AvatarGlasses.glasses02:
      return const AvatarLayerSpec(
        path: '$_root/glasses/glasses_02.png',
        left: 0.305,
        top: 0.104,
        width: 0.385,
      );

    // Dorées
    case AvatarGlasses.glasses03:
      return const AvatarLayerSpec(
        path: '$_root/glasses/glasses_03.png',
        left: 0.314,
        top: 0.101,
        width: 0.375,
      );

    // Rétro
    case AvatarGlasses.glasses04:
      return const AvatarLayerSpec(
        path: '$_root/glasses/glasses_04.png',
        left: 0.303,
        top: 0.099,
        width: 0.392,
      );
  }
}

  // ==========================================================================
  // ACCESSOIRES
  // ==========================================================================

  static AvatarLayerSpec? accessory(
    AvatarAccessory accessory,
  ) {
    switch (accessory) {
      case AvatarAccessory.none:
        return null;

      case AvatarAccessory.d20Badge:
        return const AvatarLayerSpec(
          path: '$_root/accessory/d20_badge.png',
          left: 0.455,
          top: 0.350,
          width: 0.075,
        );

      case AvatarAccessory.xpMedal:
        return const AvatarLayerSpec(
          path: '$_root/accessory/xp_medal.png',
          left: 0.455,
          top: 0.335,
          width: 0.090,
        );

      case AvatarAccessory.potion:
        return const AvatarLayerSpec(
          path: '$_root/accessory/potion.png',
          left: 0.635,
          top: 0.445,
          width: 0.085,
        );

      case AvatarAccessory.gamerPouch:
        return const AvatarLayerSpec(
          path: '$_root/accessory/gamer_pouch.png',
          left: 0.255,
          top: 0.435,
          width: 0.145,
        );

      case AvatarAccessory.heartBag:
        return const AvatarLayerSpec(
          path: '$_root/accessory/heart_bag.png',
          left: 0.255,
          top: 0.435,
          width: 0.145,
        );

      case AvatarAccessory.heartBook:
        return const AvatarLayerSpec(
          path: '$_root/accessory/heart_book.png',
          left: 0.245,
          top: 0.435,
          width: 0.155,
        );
    }
  }
}
