import 'supabase_service.dart';

class ProjectXpAdminService {
  ProjectXpAdminService._();

  // ===========================================================================
  // SAVOIR SI LE JOUEUR ACTUEL EST ADMIN
  // ===========================================================================

  static Future<bool> isCurrentUserAdmin() async {
    try {
      final dynamic response =
          await SupabaseService.client.rpc(
        'project_xp_is_admin',
      );

      return response == true;
    } catch (_) {
      // Tant que le SQL admin n'est pas installé, ou en cas d'erreur réseau,
      // l'interface se comporte simplement comme pour un joueur normal.
      return false;
    }
  }

  // ===========================================================================
  // RÉINITIALISER LES MESSAGES PUBLICS DE LA TAVERNE
  //
  // La sécurité réelle est contrôlée par Supabase.
  // Même une APK modifiée ne peut pas appeler ce RPC avec succès si
  // l'utilisateur n'est pas présent dans public.project_admins.
  // ===========================================================================

  static Future<int?> resetTavernMessages() async {
    try {
      final dynamic response =
          await SupabaseService.client.rpc(
        'project_xp_admin_reset_tavern',
      );

      if (response is int) {
        return response;
      }

      return int.tryParse(
        response?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }


  // ===========================================================================
  // SUPPRIMER UN MESSAGE PUBLIC DE LA TAVERNE
  //
  // La suppression est réalisée via un RPC SECURITY DEFINER qui vérifie
  // project_admins côté PostgreSQL. Le bouton client n'est qu'une interface :
  // les droits administrateur ne reposent jamais sur Flutter.
  // ===========================================================================

  static Future<bool> deleteTavernMessage({
    required String messageId,
  }) async {
    final String cleanMessageId =
        messageId.trim();

    if (cleanMessageId.isEmpty) {
      return false;
    }

    try {
      final dynamic response =
          await SupabaseService.client.rpc(
        'project_xp_admin_delete_tavern_message',
        params: <String, dynamic>{
          'p_message_id': cleanMessageId,
        },
      );

      return response == true;
    } catch (_) {
      return false;
    }
  }

}
