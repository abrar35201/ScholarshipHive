import 'package:signalr_netcore/signalr_client.dart';
import '../core/api_config.dart';
import 'secure_storage_service.dart';

/// Live push connection to the backend's SignalR hub. When anything changes on the
/// server (any user's attendance, a report, a router, etc.) it broadcasts one event;
/// this just forwards that "something changed" signal to whoever is listening
/// (the admin tabs), which then refetch their own data. No per-event payload parsing
/// needed — the category string is informational only.
class RealtimeService {
  final SecureStorageService _storage;
  HubConnection? _connection;

  RealtimeService(this._storage);

  Future<void> start({required void Function(String category) onChanged}) async {
    if (_connection != null) return;

    final connection = HubConnectionBuilder()
        .withUrl(
          ApiConfig.hubUrl,
          options: HttpConnectionOptions(
            accessTokenFactory: () async => await _storage.readToken() ?? '',
          ),
        )
        .withAutomaticReconnect()
        .build();

    connection.on('DataChanged', (args) {
      final category = (args != null && args.isNotEmpty) ? args[0]?.toString() ?? '' : '';
      onChanged(category);
    });

    _connection = connection;
    try {
      await connection.start();
    } catch (_) {
      // Best-effort: the admin tabs' own periodic refresh still covers this if the
      // live connection fails to establish (e.g. brief network hiccup).
      _connection = null;
    }
  }

  Future<void> stop() async {
    await _connection?.stop();
    _connection = null;
  }
}
