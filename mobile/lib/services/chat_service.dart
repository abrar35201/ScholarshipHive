import '../core/api_config.dart';
import 'api_client.dart';

class ChatTurn {
  final String role; // 'user' or 'assistant'
  final String content;
  ChatTurn({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class ChatService {
  final ApiClient _api;
  ChatService(this._api);

  Future<bool> isConfigured() async {
    final result = await _api.get(ApiConfig.adminChatStatus);
    return result['configured'] == true;
  }

  /// The assistant may run several model round-trips server-side (tool use),
  /// so this is given a much longer timeout than the rest of the app's calls.
  Future<String> ask(String message, {int? scopedUserId, List<ChatTurn> history = const []}) async {
    final result = await _api.post(
      ApiConfig.adminChat,
      {
        'message': message,
        if (scopedUserId != null) 'scopedUserId': scopedUserId,
        'history': history.map((h) => h.toJson()).toList(),
      },
      // Up to six Gemini tool rounds may be needed for a multi-part question.
      receiveTimeout: const Duration(minutes: 5),
    );
    return result['reply'] as String? ?? "Sorry, I couldn't come up with an answer.";
  }
}
