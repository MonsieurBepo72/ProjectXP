import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AvatarGenerationService {
  // Mode développement gratuit.
  // Aucune API ni génération IA réelle.
  static const bool isMockMode = true;

  static Future<String> generateFromPhoto(
    String photoPath,
  ) async {
    final File sourceFile = File(photoPath);

    if (!await sourceFile.exists()) {
      throw Exception(
        'La photo sélectionnée est introuvable.',
      );
    }

    // Simulation d'une génération IA.
    await Future.delayed(
      const Duration(seconds: 2),
    );

    final Directory appDirectory =
        await getApplicationDocumentsDirectory();

    final Directory avatarDirectory = Directory(
      '${appDirectory.path}'
      '${Platform.pathSeparator}'
      'avatars',
    );

    if (!await avatarDirectory.exists()) {
      await avatarDirectory.create(
        recursive: true,
      );
    }

    final String extension =
        _getExtension(photoPath);

    final String fileName =
        'mock_avatar_'
        '${DateTime.now().millisecondsSinceEpoch}'
        '$extension';

    final File destinationFile = File(
      '${avatarDirectory.path}'
      '${Platform.pathSeparator}'
      '$fileName',
    );

    await sourceFile.copy(
      destinationFile.path,
    );

    return destinationFile.path;
  }

  static String _getExtension(
    String path,
  ) {
    final String lowerPath =
        path.toLowerCase();

    if (lowerPath.endsWith('.png')) {
      return '.png';
    }

    if (lowerPath.endsWith('.webp')) {
      return '.webp';
    }

    if (lowerPath.endsWith('.heic')) {
      return '.heic';
    }

    return '.jpg';
  }
}