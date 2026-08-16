enum AvatarCreationMode {
  manual,
  photo,
}

// ============================================================================
// OPTIONS DE PERSONNALISATION
// ============================================================================

enum AvatarSkin {
  body01,
  body02,
  body03,
  body04,
}

enum AvatarHair {
  none,
  hair02,
  hair03,
  hair04,
  hair05,
  hair06,
}

enum AvatarBeard {
  none,
  beard02,
  beard03,
  beard04,
  beard05,
}

enum AvatarOutfit {
  outfit01,
  outfit02,
  outfit03,
  outfit04,
}

enum AvatarAccessory {
  none,
  d20Badge,
  xpMedal,
  potion,
  gamerPouch,
  heartBag,
  heartBook,
}

enum AvatarGlasses {
  none,
  glasses01,
  glasses02,
  glasses03,
  glasses04,
}

// ============================================================================
// AVATAR MODEL
// ============================================================================

class AvatarModel {
  final String userId;
  final AvatarCreationMode creationMode;

  final String? generatedImagePath;

  // Conservés pour relire les anciennes sauvegardes.
  final String? faceStyle;
  final String? hairColor;

  final AvatarSkin skin;
  final AvatarHair hair;
  final AvatarBeard beard;
  final AvatarOutfit outfit;
  final AvatarAccessory accessory;
  final AvatarGlasses glasses;

  final DateTime createdAt;
  final DateTime updatedAt;

  AvatarModel({
    required this.userId,
    required this.creationMode,
    this.generatedImagePath,
    this.faceStyle,
    this.hairColor,
    AvatarSkin? skin,
    AvatarHair? hair,
    AvatarBeard? beard,
    AvatarOutfit? outfit,
    AvatarAccessory? accessory,
    AvatarGlasses? glasses,

    // Ancien format.
    String? skinTone,
    String? hairStyle,
    String? beardStyle,
    String? outfitStyle,
    String? accessoryStyle,

    required this.createdAt,
    required this.updatedAt,
  })  : skin = skin ?? _skinFromOldValue(skinTone),
        hair = hair ?? _hairFromOldValue(hairStyle),
        beard = beard ?? _beardFromOldValue(beardStyle),
        outfit = outfit ?? _outfitFromOldValue(outfitStyle),
        accessory =
            accessory ?? _accessoryFromOldValue(accessoryStyle),
        glasses =
            glasses ?? _glassesFromOldValue(accessoryStyle);

  // ==========================================================================
  // LIBELLÉS
  // ==========================================================================

  String get skinTone {
    switch (skin) {
      case AvatarSkin.body01:
        return 'Clair';
      case AvatarSkin.body02:
        return 'Doré';
      case AvatarSkin.body03:
        return 'Mat';
      case AvatarSkin.body04:
        return 'Foncé';
    }
  }

  String get hairStyle {
    switch (hair) {
      case AvatarHair.none:
        return 'Aucun';
      case AvatarHair.hair02:
        return 'Coiffure 1';
      case AvatarHair.hair03:
        return 'Coiffure 2';
      case AvatarHair.hair04:
        return 'Coiffure 3';
      case AvatarHair.hair05:
        return 'Coiffure 4';
      case AvatarHair.hair06:
        return 'Coiffure 5';
    }
  }

  String get beardStyle {
    switch (beard) {
      case AvatarBeard.none:
        return 'Aucune';
      case AvatarBeard.beard02:
        return 'Barbe 1';
      case AvatarBeard.beard03:
        return 'Barbe 2';
      case AvatarBeard.beard04:
        return 'Barbe 3';
      case AvatarBeard.beard05:
        return 'Barbe 4';
    }
  }

  String get outfitStyle {
    switch (outfit) {
      case AvatarOutfit.outfit01:
        return 'Aventurier';
      case AvatarOutfit.outfit02:
        return 'Mage';
      case AvatarOutfit.outfit03:
        return 'Rôdeur';
      case AvatarOutfit.outfit04:
        return 'Tavernier';
    }
  }

  String get accessoryStyle {
    switch (accessory) {
      case AvatarAccessory.none:
        return 'Aucun';
      case AvatarAccessory.d20Badge:
        return 'D20';
      case AvatarAccessory.xpMedal:
        return 'Médaille XP';
      case AvatarAccessory.potion:
        return 'Potion';
      case AvatarAccessory.gamerPouch:
        return 'Gamer pouch';
      case AvatarAccessory.heartBag:
        return 'Sac cœur';
      case AvatarAccessory.heartBook:
        return 'Livre cœur';
    }
  }

  String get glassesStyle {
    switch (glasses) {
      case AvatarGlasses.none:
        return 'Aucune';
      case AvatarGlasses.glasses01:
        return 'Lunettes 1';
      case AvatarGlasses.glasses02:
        return 'Lunettes 2';
      case AvatarGlasses.glasses03:
        return 'Lunettes 3';
      case AvatarGlasses.glasses04:
        return 'Lunettes 4';
    }
  }

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  AvatarModel copyWith({
    String? userId,
    AvatarCreationMode? creationMode,
    String? generatedImagePath,
    bool clearGeneratedImagePath = false,
    String? faceStyle,
    String? hairColor,
    AvatarSkin? skin,
    AvatarHair? hair,
    AvatarBeard? beard,
    AvatarOutfit? outfit,
    AvatarAccessory? accessory,
    AvatarGlasses? glasses,

    // Ancien éditeur.
    String? skinTone,
    String? hairStyle,
    String? beardStyle,
    String? outfitStyle,
    String? accessoryStyle,

    DateTime? updatedAt,
  }) {
    return AvatarModel(
      userId: userId ?? this.userId,
      creationMode: creationMode ?? this.creationMode,
      generatedImagePath: clearGeneratedImagePath
          ? null
          : generatedImagePath ?? this.generatedImagePath,
      faceStyle: faceStyle ?? this.faceStyle,
      hairColor: hairColor ?? this.hairColor,
      skin: skin ??
          (skinTone != null
              ? _skinFromOldValue(skinTone)
              : this.skin),
      hair: hair ??
          (hairStyle != null
              ? _hairFromOldValue(hairStyle)
              : this.hair),
      beard: beard ??
          (beardStyle != null
              ? _beardFromOldValue(beardStyle)
              : this.beard),
      outfit: outfit ??
          (outfitStyle != null
              ? _outfitFromOldValue(outfitStyle)
              : this.outfit),
      accessory: accessory ??
          (accessoryStyle != null
              ? _accessoryFromOldValue(accessoryStyle)
              : this.accessory),
      glasses: glasses ?? this.glasses,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // ==========================================================================
  // JSON
  // ==========================================================================

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'creationMode': creationMode.name,
      'generatedImagePath': generatedImagePath,
      'faceStyle': faceStyle,
      'hairColor': hairColor,

      'skin': skin.name,
      'hair': hair.name,
      'beard': beard.name,
      'outfit': outfit.name,
      'accessory': accessory.name,
      'glasses': glasses.name,

      // On garde aussi ces clés pendant la migration.
      'skinTone': skinTone,
      'hairStyle': hairStyle,
      'beardStyle': beardStyle,
      'outfitStyle': outfitStyle,
      'accessoryStyle': accessoryStyle,

      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AvatarModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final DateTime now = DateTime.now();

    return AvatarModel(
      userId: json['userId'] as String? ?? 'unknown',
      creationMode: _creationModeFromJson(
        json['creationMode'],
      ),
      generatedImagePath:
          json['generatedImagePath'] as String?,
      faceStyle: json['faceStyle'] as String?,
      hairColor: json['hairColor'] as String?,

      skin: _skinFromJson(
        json['skin'],
        json['skinTone'],
      ),
      hair: _hairFromJson(
        json['hair'],
        json['hairStyle'],
      ),
      beard: _beardFromJson(
        json['beard'],
        json['beardStyle'],
      ),
      outfit: _outfitFromJson(
        json['outfit'],
        json['outfitStyle'],
      ),
      accessory: _accessoryFromJson(
        json['accessory'],
        json['accessoryStyle'],
      ),
      glasses: _glassesFromJson(
        json['glasses'],
        json['accessoryStyle'],
      ),

      skinTone: json['skinTone'] as String?,
      hairStyle: json['hairStyle'] as String?,
      beardStyle: json['beardStyle'] as String?,
      outfitStyle: json['outfitStyle'] as String?,
      accessoryStyle:
          json['accessoryStyle'] as String?,

      createdAt: DateTime.tryParse(
            json['createdAt'] as String? ?? '',
          ) ??
          now,
      updatedAt: DateTime.tryParse(
            json['updatedAt'] as String? ?? '',
          ) ??
          now,
    );
  }

  // ==========================================================================
  // MIGRATION
  // ==========================================================================

  static AvatarCreationMode _creationModeFromJson(
    dynamic value,
  ) {
    return AvatarCreationMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AvatarCreationMode.manual,
    );
  }

  static AvatarSkin _skinFromJson(
    dynamic value,
    dynamic oldValue,
  ) {
    switch (value) {
      case 'body01':
      case 'light':
        return AvatarSkin.body01;
      case 'body02':
      case 'tan':
        return AvatarSkin.body02;
      case 'body03':
      case 'dark':
        return AvatarSkin.body03;
      case 'body04':
        return AvatarSkin.body04;
      default:
        return _skinFromOldValue(
          oldValue as String?,
        );
    }
  }

  static AvatarHair _hairFromJson(
    dynamic value,
    dynamic oldValue,
  ) {
    switch (value) {
      case 'none':
        return AvatarHair.none;
      case 'hair02':
      case 'hair_02':
      case 'shortBrown':
        return AvatarHair.hair02;
      case 'hair03':
      case 'hair_03':
      case 'messyBrown':
        return AvatarHair.hair03;
      case 'hair04':
      case 'hair_04':
      case 'sweptDark':
        return AvatarHair.hair04;
      case 'hair05':
      case 'hair_05':
      case 'longBrown':
        return AvatarHair.hair05;
      case 'hair06':
      case 'hair_06':
        return AvatarHair.hair06;
      default:
        return _hairFromOldValue(
          oldValue as String?,
        );
    }
  }

  static AvatarBeard _beardFromJson(
    dynamic value,
    dynamic oldValue,
  ) {
    switch (value) {
      case 'none':
        return AvatarBeard.none;
      case 'beard02':
      case 'beard_02':
      case 'shortBrown':
        return AvatarBeard.beard02;
      case 'beard03':
      case 'beard_03':
      case 'trimmedDark':
        return AvatarBeard.beard03;
      case 'beard04':
      case 'beard_04':
      case 'nordicBrown':
        return AvatarBeard.beard04;
      case 'beard05':
      case 'beard_05':
        return AvatarBeard.beard05;
      default:
        return _beardFromOldValue(
          oldValue as String?,
        );
    }
  }

  static AvatarOutfit _outfitFromJson(
    dynamic value,
    dynamic oldValue,
  ) {
    switch (value) {
      case 'outfit01':
      case 'outfit_01':
      case 'adventurerGreen':
        return AvatarOutfit.outfit01;
      case 'outfit02':
      case 'outfit_02':
      case 'mageBlue':
        return AvatarOutfit.outfit02;
      case 'outfit03':
      case 'outfit_03':
      case 'rogueDark':
        return AvatarOutfit.outfit03;
      case 'outfit04':
      case 'outfit_04':
      case 'tavernBrown':
        return AvatarOutfit.outfit04;
      default:
        return _outfitFromOldValue(
          oldValue as String?,
        );
    }
  }

  static AvatarAccessory _accessoryFromJson(
    dynamic value,
    dynamic oldValue,
  ) {
    switch (value) {
      case 'none':
        return AvatarAccessory.none;
      case 'd20Badge':
      case 'd20_badge':
        return AvatarAccessory.d20Badge;
      case 'xpMedal':
      case 'xp_medal':
        return AvatarAccessory.xpMedal;
      case 'potion':
        return AvatarAccessory.potion;
      case 'gamerPouch':
      case 'gamer_pouch':
        return AvatarAccessory.gamerPouch;
      case 'heartBag':
      case 'heart_bag':
        return AvatarAccessory.heartBag;
      case 'heartBook':
      case 'heart_book':
        return AvatarAccessory.heartBook;
      default:
        return _accessoryFromOldValue(
          oldValue as String?,
        );
    }
  }

  static AvatarGlasses _glassesFromJson(
    dynamic value,
    dynamic oldValue,
  ) {
    switch (value) {
      case 'none':
        return AvatarGlasses.none;
      case 'glasses01':
      case 'glasses_01':
      case 'roundBlack':
        return AvatarGlasses.glasses01;
      case 'glasses02':
      case 'glasses_02':
        return AvatarGlasses.glasses02;
      case 'glasses03':
      case 'glasses_03':
        return AvatarGlasses.glasses03;
      case 'glasses04':
      case 'glasses_04':
        return AvatarGlasses.glasses04;
      default:
        return _glassesFromOldValue(
          oldValue as String?,
        );
    }
  }

  static AvatarSkin _skinFromOldValue(
    String? value,
  ) {
    switch (value) {
      case 'Foncé':
      case 'Base 3':
        return AvatarSkin.body03;
      case 'Mat':
      case 'Doré':
      case 'Asiatique':
      case 'Base 2':
        return AvatarSkin.body02;
      case 'Base 4':
        return AvatarSkin.body04;
      case 'Clair':
      case 'Base 1':
      default:
        return AvatarSkin.body01;
    }
  }

  static AvatarHair _hairFromOldValue(
    String? value,
  ) {
    switch (value) {
      case 'Rasé':
      case 'Aucun':
      case 'Aucune':
        return AvatarHair.none;
      case 'Mi-long':
        return AvatarHair.hair05;
      case 'Court':
      default:
        return AvatarHair.hair02;
    }
  }

  static AvatarBeard _beardFromOldValue(
    String? value,
  ) {
    switch (value) {
      case 'Courte':
        return AvatarBeard.beard02;
      case 'Nordique':
      case 'Longue':
        return AvatarBeard.beard04;
      case 'Bouc':
        return AvatarBeard.beard05;
      case 'Aucune':
      default:
        return AvatarBeard.none;
    }
  }

  static AvatarOutfit _outfitFromOldValue(
    String? value,
  ) {
    switch (value) {
      case 'Mage':
        return AvatarOutfit.outfit02;
      case 'Rôdeur':
      case 'Guerrier':
        return AvatarOutfit.outfit03;
      case 'Tavernier':
        return AvatarOutfit.outfit04;
      case 'Aventurier':
      default:
        return AvatarOutfit.outfit01;
    }
  }

  static AvatarAccessory _accessoryFromOldValue(
    String? value,
  ) {
    switch (value) {
      case 'D20':
        return AvatarAccessory.d20Badge;
      case 'XP':
      case 'Médaille XP':
        return AvatarAccessory.xpMedal;
      case 'Potion':
        return AvatarAccessory.potion;
      case 'Gaming':
      case 'Gamer pouch':
        return AvatarAccessory.gamerPouch;
      case 'Sac cœur':
        return AvatarAccessory.heartBag;
      case 'Livre cœur':
        return AvatarAccessory.heartBook;
      default:
        return AvatarAccessory.none;
    }
  }

  static AvatarGlasses _glassesFromOldValue(
    String? value,
  ) {
    if (value == 'Lunettes') {
      return AvatarGlasses.glasses01;
    }

    return AvatarGlasses.none;
  }
}
