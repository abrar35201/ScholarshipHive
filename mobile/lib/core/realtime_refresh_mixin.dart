import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

/// Mix into a tab's State to auto-refresh the instant the server pushes a live
/// "DataChanged" event (see AppProvider.realtimeTick), instead of waiting for the
/// next periodic poll or a manual pull-to-refresh.
mixin RealtimeRefreshMixin<T extends StatefulWidget> on State<T> {
  int _lastRealtimeTick = 0;
  // Captured once while context is still safe to read, rather than looked up
  // again in stopListeningForRealtimeChanges() — by the time dispose() runs,
  // the element can already be deactivated, and Provider.of/context.read at
  // that point throws "Looking up a deactivated widget's ancestor is unsafe."
  AppProvider? _appProvider;

  void onRealtimeChanged();

  void startListeningForRealtimeChanges() {
    final provider = context.read<AppProvider>();
    _appProvider = provider;
    _lastRealtimeTick = provider.realtimeTick;
    provider.addListener(_checkRealtimeTick);
  }

  void stopListeningForRealtimeChanges() {
    _appProvider?.removeListener(_checkRealtimeTick);
  }

  void _checkRealtimeTick() {
    final tick = _appProvider?.realtimeTick ?? _lastRealtimeTick;
    if (tick != _lastRealtimeTick) {
      _lastRealtimeTick = tick;
      onRealtimeChanged();
    }
  }
}
