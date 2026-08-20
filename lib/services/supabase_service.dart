import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  // ===========================================================================
  // CLIENT SUPABASE
  //
  // Permet aux autres parties de Project XP d'accéder facilement à Supabase.
  // ===========================================================================

  static SupabaseClient get client {
    return Supabase.instance.client;
  }

  // ===========================================================================
  // UTILISATEUR SUPABASE ACTUEL
  // ===========================================================================

  static User? get currentUser {
    return client.auth.currentUser;
  }

  // ===========================================================================
  // SESSION SOCIALE PROJECT XP
  //
  // Si une session Supabase existe déjà :
  // → on la conserve.
  //
  // Si aucune session n'existe :
  // → on crée automatiquement un utilisateur anonyme.
  //
  // Cela ne remplace PAS encore le système de compte actuel de Project XP.
  // Supabase sert pour l'instant uniquement de couche sociale pour la Taverne.
  // ===========================================================================

  static Future<User?> ensureAnonymousSession() async {
    final User? existingUser = currentUser;

    if (existingUser != null) {
      return existingUser;
    }

    final AuthResponse response =
        await client.auth.signInAnonymously();

    return response.user;
  }
}