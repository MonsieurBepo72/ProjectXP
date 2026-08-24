import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

class PushDeviceTokenService {
  PushDeviceTokenService._();

  static Future<bool> saveToken({
    required String token,
    String platform = 'android',
  }) async {
    final String cleanToken = token.trim();

    if (cleanToken.isEmpty) {
      return false;
    }

    final user = SupabaseService.currentUser;

    if (user == null) {
      debugPrint(
        'Token FCM non enregistré : aucune session Supabase.',
      );
      return false;
    }

    try {
      await SupabaseService.client
          .from('push_device_tokens')
          .upsert(
        <String, dynamic>{
          'user_id': user.id,
          'token': cleanToken,
          'platform': platform,
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      );

      debugPrint(
        'Token FCM enregistré dans Supabase.',
      );

      return true;
    } catch (error) {
      debugPrint(
        'Impossible d’enregistrer le token FCM : $error',
      );

      return false;
    }
  }

  static Future<bool> replaceToken({
    required String oldToken,
    required String newToken,
    String platform = 'android',
  }) async {
    final String cleanOldToken =
        oldToken.trim();

    final String cleanNewToken =
        newToken.trim();

    if (cleanNewToken.isEmpty) {
      return false;
    }

    if (cleanOldToken.isNotEmpty &&
        cleanOldToken != cleanNewToken) {
      await removeToken(
        cleanOldToken,
      );
    }

    return saveToken(
      token: cleanNewToken,
      platform: platform,
    );
  }

  static Future<bool> removeToken(
    String token,
  ) async {
    final String cleanToken = token.trim();

    if (cleanToken.isEmpty) {
      return true;
    }

    final user = SupabaseService.currentUser;

    if (user == null) {
      return false;
    }

    try {
      await SupabaseService.client
          .from('push_device_tokens')
          .delete()
          .eq(
            'user_id',
            user.id,
          )
          .eq(
            'token',
            cleanToken,
          );

      debugPrint(
        'Ancien token FCM retiré de Supabase.',
      );

      return true;
    } catch (error) {
      debugPrint(
        'Impossible de retirer le token FCM : $error',
      );

      return false;
    }
  }
}
