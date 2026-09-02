import 'supabase_service.dart';
import 'tavern_profile_service.dart';

class CompagniePlayerService {
  CompagniePlayerService._();

  /// Charge les profils publics réellement synchronisés dans Supabase.
  ///
  /// La table tavern_profiles est déjà la source publique utilisée par la
  /// Taverne et le Communicateur. On la réutilise ici afin de ne pas créer
  /// une deuxième identité publique pour Compagnie.
  static Future<List<Map<String, dynamic>>> loadPublicPlayers() async {
    final currentUser = SupabaseService.currentUser;

    if (currentUser == null) {
      return <Map<String, dynamic>>[];
    }

    // Garantit que le profil public de l'utilisateur courant est à jour avant
    // d'afficher les autres joueurs.
    await TavernProfileService.syncCurrentProfile();

    final List<dynamic> response = await SupabaseService.client
        .from('tavern_profiles')
        .select(
          'id, display_name, avatar_url, avatar_data, '
          'public_profile_data, updated_at',
        );

    final List<Map<String, dynamic>> players = response
        .map(
          (dynamic item) => Map<String, dynamic>.from(
            item as Map,
          ),
        )
        .where(
          (Map<String, dynamic> profile) {
            final String id =
                profile['id']?.toString().trim() ?? '';

            return id.isNotEmpty && id != currentUser.id;
          },
        )
        .toList();

    players.sort(
      (
        Map<String, dynamic> a,
        Map<String, dynamic> b,
      ) {
        final String nameA =
            a['display_name']?.toString().trim().toLowerCase() ?? '';

        final String nameB =
            b['display_name']?.toString().trim().toLowerCase() ?? '';

        return nameA.compareTo(nameB);
      },
    );

    return players;
  }
}
