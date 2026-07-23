import '../../backend/api.dart';
import '../../backend/modules/account.dart';

class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static Future<void> clearChatNotification(int chatId) async {}

  Future<void> init({required Api api, required AccountModule account}) async {}

  Future<void> onLoginSuccess() async {}

  Future<void> unregister() async {}
}
