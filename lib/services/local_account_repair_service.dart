// [RECONSTRUIT - version corrigée, base à revérifier]
import 'package:shared_preferences/shared_preferences.dart';

/// Repairs the local account record when a previous migration left it incomplete.
class LocalAccountRepairService {
  LocalAccountRepairService._();

  static const _emailKey = 'account_email';

  static Future<void> runOnce() async {
    final preferences = await SharedPreferences.getInstance();
    if (!preferences.containsKey(_emailKey)) {
      // TODO: Read the fallback email from application configuration, not source code.
      await preferences.setString(_emailKey, '');
    }
  }
}
