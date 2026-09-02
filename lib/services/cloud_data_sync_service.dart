import 'avatar_storage.dart';
import 'cloud_data_service.dart';
import 'game_library_service.dart';
import 'profile_storage.dart';

class CloudDataSyncService {
  CloudDataSyncService._();

  static Future<void> syncCurrentAccount() async {
    if (CloudDataService.permanentUser == null) {
      return;
    }

    // Ordre volontaire : le profil et l'avatar sont restaurés avant les écrans
    // sociaux / le Portail, puis la Bibliothèque et le Fil d'Aventure suivent.
    await ProfileStorage.syncCurrentProfileWithCloud();
    await AvatarStorage.syncCurrentAvatarWithCloud();
    await GameLibraryService.syncCurrentDataWithCloud();
  }
}
