import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class PhoneWallpaperService {
  PhoneWallpaperService._();

  static const String _preferencePrefix =
      'project_xp_phone_wallpaper_v1_';

  static final ImagePicker _picker =
      ImagePicker();

  static Future<String?> loadCurrentWallpaperPath() async {
    final String userId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    if (userId.isEmpty) {
      return null;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String path =
        prefs.getString('$_preferencePrefix$userId')?.trim() ?? '';

    if (path.isEmpty) {
      return null;
    }

    final File file = File(path);

    if (!await file.exists()) {
      await prefs.remove('$_preferencePrefix$userId');
      return null;
    }

    return path;
  }

  static Future<String?> pickAndSaveCurrentWallpaper() async {
    final String userId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    if (userId.isEmpty) {
      return null;
    }

    final XFile? picked =
        await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2160,
      maxHeight: 2160,
    );

    if (picked == null) {
      return null;
    }

    final Directory documents =
        await getApplicationDocumentsDirectory();

    final Directory wallpaperDirectory =
        Directory(
      '${documents.path}${Platform.pathSeparator}'
      'project_xp${Platform.pathSeparator}wallpapers',
    );

    if (!await wallpaperDirectory.exists()) {
      await wallpaperDirectory.create(
        recursive: true,
      );
    }

    final String safeUserId =
        userId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );

    final String extension =
        _safeExtension(picked.path);

    // Un nom unique à chaque sélection évite que Flutter réutilise
    // l'ancienne image depuis son cache FileImage lorsque le chemin reste
    // identique. C'était la cause du fond d'écran qui revenait toujours à la
    // première photo choisie.
    final String revision =
        DateTime.now().microsecondsSinceEpoch.toString();

    final File destination =
        File(
      '${wallpaperDirectory.path}${Platform.pathSeparator}'
      'wallpaper_${safeUserId}_$revision$extension',
    );

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? previousPath =
        prefs.getString('$_preferencePrefix$userId');

    await File(picked.path).copy(
      destination.path,
    );

    await prefs.setString(
      '$_preferencePrefix$userId',
      destination.path,
    );

    if (previousPath != null &&
        previousPath.isNotEmpty &&
        previousPath != destination.path) {
      final File previousFile =
          File(previousPath);

      try {
        if (await previousFile.exists()) {
          await previousFile.delete();
        }
      } catch (_) {
        // Une ancienne image impossible à supprimer ne bloque pas la nouvelle.
      }
    }

    return destination.path;
  }

  static Future<bool> clearCurrentWallpaper() async {
    final String userId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    if (userId.isEmpty) {
      return false;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String key =
        '$_preferencePrefix$userId';

    final String path =
        prefs.getString(key)?.trim() ?? '';

    if (path.isNotEmpty) {
      try {
        final File file = File(path);

        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Le réglage peut être réinitialisé même si le fichier a déjà disparu.
      }
    }

    return prefs.remove(key);
  }

  static String _safeExtension(
    String path,
  ) {
    final int slash =
        path.lastIndexOf(RegExp(r'[/\\]'));

    final int dot =
        path.lastIndexOf('.');

    if (dot <= slash ||
        dot == -1 ||
        path.length - dot > 6) {
      return '.jpg';
    }

    final String extension =
        path.substring(dot).toLowerCase();

    const Set<String> allowed =
        <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
    };

    return allowed.contains(extension)
        ? extension
        : '.jpg';
  }
}
