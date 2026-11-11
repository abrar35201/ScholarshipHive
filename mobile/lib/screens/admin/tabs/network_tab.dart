import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../../../core/api_exception.dart';
import '../../../core/app_theme.dart';
import '../../../core/realtime_refresh_mixin.dart';
import '../../../models/admin_models.dart';
import '../../../providers/app_provider.dart';
import 'location_picker_screen.dart';

class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key});

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> with RealtimeRefreshMixin {
  // Fallback only — live pushes (see RealtimeRefreshMixin) cover the normal case;
  // this just guards against a missed/dropped push.
  static const _autoRefreshInterval = Duration(seconds: 60);

  List<AdminRouter>? _routers;
  List<AdminPendingNetwork>? _pending;
  List<AdminLocation>? _locations;
  String? _error;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) => _load());
    startListeningForRealtimeChanges();
  }

  @override
  void onRealtimeChanged() => _load();

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    stopListeningForRealtimeChanges();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppProvider>().adminApiService;
      final results = await Future.wait([api.routers(), api.pendingNetworks(), api.locations()]);
      if (!mounted) return;
      setState(() {
        _routers = results[0] as List<AdminRouter>;
        _pending = results[1] as List<AdminPendingNetwork>;
        _locations = results[2] as List<AdminLocation>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _refresh() => _load();

  Future<void> _approvePending(AdminPendingNetwork p) async {
    await context.read<AppProvider>().adminApiService.approvePendingNetwork(p.id);
    await _refresh();
  }

  Future<void> _dismissPending(AdminPendingNetwork p) async {
    await context.read<AppProvider>().adminApiService.dismissPendingNetwork(p.id);
    await _refresh();
  }

  Future<void> _toggleRouter(AdminRouter r) async {
    await context.read<AppProvider>().adminApiService.toggleRouterActive(r);
    await _refresh();
  }

  Future<void> _deleteRouter(AdminRouter r) async {
    await context.read<AppProvider>().adminApiService.deleteRouter(r.id);
    await _refresh();
  }

  Future<void> _addCurrentNetwork() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddRouterSheet(),
    );
    if (result == true) await _refresh();
  }

  Future<void> _addRouterManually() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ManualAddRouterSheet(),
    );
    if (result == true) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Router added successfully.')));
      }
    }
  }

  Future<void> _scanNearby() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ScanNetworksSheet(),
    );
    if (result == true) await _refresh();
  }

  Future<void> _addLocation() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddLocationSheet(),
    );
    if (result == true) await _refresh();
  }

  Future<void> _toggleLocation(AdminLocation l) async {
    await context.read<AppProvider>().adminApiService.toggleLocationActive(l);
    await _refresh();
  }

  Future<void> _deleteLocation(AdminLocation l) async {
    await context.read<AppProvider>().adminApiService.deleteLocation(l.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _addCurrentNetwork,
                    icon: const Icon(Icons.wifi_rounded, size: 18),
                    label: const Text('Add Current Network'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanNearby,
                    icon: const Icon(Icons.wifi_find_rounded, size: 18),
                    label: const Text('Scan Nearby'),
                  ),
                ),
              ],
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addRouterManually,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Router Manually'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Builder(
              builder: (context) {
                if (_pending == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final pending = _pending!;
                if (pending.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending Networks (${pending.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Captured automatically when a device tried connecting from here.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                    ),
                    const SizedBox(height: 10),
                    ...pending.map(
                      (p) => Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppColors.primarySoft),
                        ),
                        elevation: 0,
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.wifi_tethering_rounded, color: AppColors.warning, size: 18),
                          ),
                          title: Text(p.ssid ?? '(unknown name)', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${p.bssid} · ${p.attemptCount} attempt(s)'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
                                onPressed: () => _approvePending(p),
                                tooltip: 'Approve',
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: AppColors.danger),
                                onPressed: () => _dismissPending(p),
                                tooltip: 'Dismiss',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
            Text(
              'Approved Routers',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                if (_routers == null) {
                  if (_error != null) return Text('Error: $_error');
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final routers = _routers!;
                if (routers.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(child: Text('No routers yet.')),
                  );
                }
                return Column(
                  children: routers
                      .map(
                        (r) => Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: AppColors.primarySoft),
                          ),
                          elevation: 0,
                          child: ListTile(
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: r.isActive
                                    ? AppColors.success.withValues(alpha: 0.12)
                                    : AppColors.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.router_rounded,
                                color: r.isActive ? AppColors.success : AppColors.danger,
                                size: 18,
                              ),
                            ),
                            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(r.bssid),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(value: r.isActive, onChanged: (_) => _toggleRouter(r)),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                  onPressed: () => _deleteRouter(r),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Office Locations (Geofence)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  onPressed: _addLocation,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Wakes the attendance monitor on arrival/departure so it doesn\'t need to run nonstop in the background. Doesn\'t replace the router check above.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final locations = _locations;
                if (locations == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (locations.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(child: Text('No office locations yet.')),
                  );
                }
                return Column(
                  children: locations
                      .map(
                        (l) => Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: AppColors.primarySoft),
                          ),
                          elevation: 0,
                          child: ListTile(
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: l.isActive
                                    ? AppColors.success.withValues(alpha: 0.12)
                                    : AppColors.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: l.isActive ? AppColors.success : AppColors.danger,
                                size: 18,
                              ),
                            ),
                            title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${l.latitude.toStringAsFixed(6)}, ${l.longitude.toStringAsFixed(6)} · ${l.radiusMeters.round()}m radius',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(value: l.isActive, onChanged: (_) => _toggleLocation(l)),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                  onPressed: () => _deleteLocation(l),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _AddRouterSheet extends StatefulWidget {
  const _AddRouterSheet();

  @override
  State<_AddRouterSheet> createState() => _AddRouterSheetState();
}

class _AddRouterSheetState extends State<_AddRouterSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _detecting = true;
  bool _busy = false;
  String? _error;
  String? _detectedBssid;
  String? _detectedSsid;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Reads whatever network THIS phone is currently connected to — the admin never
  /// needs to know what a BSSID is or type one in themselves.
  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _error = null;
    });

    if (kIsWeb) {
      setState(() {
        _detecting = false;
        _error = 'Browsers cannot read a Wi-Fi router BSSID. Use Add Router Manually to enter it.';
      });
      return;
    }

    final networkService = context.read<AppProvider>().networkService;
    final hasPermission = await networkService.ensurePermissions();
    if (!hasPermission) {
      setState(() {
        _detecting = false;
        _error = 'Location permission is needed to read the Wi-Fi network. Please allow it, then try again.';
      });
      return;
    }

    final bssid = await networkService.getDeviceBssid();
    if (bssid == null) {
      setState(() {
        _detecting = false;
        _error = 'Not connected to a Wi-Fi network right now. Connect to the router you want to add, then try again.';
      });
      return;
    }

    final ssid = await networkService.getDeviceSsid();
    setState(() {
      _detecting = false;
      _detectedBssid = bssid;
      _detectedSsid = ssid;
      _name.text = ssid ?? bssid;
    });
  }

  Future<void> _submit() async {
    if (_detectedBssid == null || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppProvider>().adminApiService.addRouter(name: _name.text.trim(), bssid: _detectedBssid!);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add This Network',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Connect your phone to the router\'s Wi-Fi, then add it — nothing technical to type.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          if (_detecting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: _detect, child: const Text('Try Again')),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.wifi_rounded, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connected to: ${_detectedSsid ?? _detectedBssid}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name (so you recognize it later)'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Add This Network'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManualAddRouterSheet extends StatefulWidget {
  const _ManualAddRouterSheet();

  @override
  State<_ManualAddRouterSheet> createState() => _ManualAddRouterSheetState();
}

class _ManualAddRouterSheetState extends State<_ManualAddRouterSheet> {
  static final _bssidPattern = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$');
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _bssid = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bssid.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final bssid = _bssid.text.trim().replaceAll('-', ':').toUpperCase();
    try {
      await context.read<AppProvider>().adminApiService.addRouter(name: _name.text.trim(), bssid: bssid);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not add the router. Check your connection and try again.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Router Manually',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Router Name / SSID'),
                textInputAction: TextInputAction.next,
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bssid,
                decoration: const InputDecoration(labelText: 'BSSID (MAC address)', hintText: 'AA:BB:CC:DD:EE:FF'),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                maxLength: 17,
                validator: (value) {
                  final bssid = value?.trim() ?? '';
                  if (bssid.isEmpty) return 'Required';
                  if (!_bssidPattern.hasMatch(bssid)) return 'Enter a valid MAC address, e.g. AA:BB:CC:DD:EE:FF';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add Router'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets an admin see every Wi-Fi network their phone can currently detect (not just
/// the one it's connected to) and add several at once — useful when one physical
/// location broadcasts more than one network, e.g. separate 2.4GHz/5GHz bands.
class _ScanNetworksSheet extends StatefulWidget {
  const _ScanNetworksSheet();

  @override
  State<_ScanNetworksSheet> createState() => _ScanNetworksSheetState();
}

class _ScanNetworksSheetState extends State<_ScanNetworksSheet> {
  bool _scanning = true;
  bool _adding = false;
  String? _error;
  List<WiFiAccessPoint> _results = [];
  final Set<String> _selectedBssids = {};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });

    if (kIsWeb) {
      setState(() {
        _scanning = false;
        _error = 'Browsers cannot scan nearby Wi-Fi networks. Use the Android app to add a router from this device.';
      });
      return;
    }

    try {
      final canStart = await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canStart != CanStartScan.yes) {
        setState(() {
          _scanning = false;
          _error = 'Can\'t scan for networks on this device right now. Make sure Wi-Fi and Location are turned on.';
        });
        return;
      }

      await WiFiScan.instance.startScan();
      await Future.delayed(const Duration(seconds: 2));

      final canGet = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
      if (canGet != CanGetScannedResults.yes) {
        setState(() {
          _scanning = false;
          _error = 'Can\'t read scan results on this device right now.';
        });
        return;
      }

      final results = await WiFiScan.instance.getScannedResults();
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _results = results;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'Wi-Fi scanning is unavailable on this device right now.';
      });
    }
  }

  Future<void> _addSelected() async {
    setState(() => _adding = true);
    final api = context.read<AppProvider>().adminApiService;
    for (final bssid in _selectedBssids) {
      final ap = _results.firstWhere((r) => r.bssid == bssid);
      try {
        await api.addRouter(name: ap.ssid.isNotEmpty ? ap.ssid : ap.bssid, bssid: ap.bssid);
      } on ApiException {
        // Already added or otherwise rejected — skip it and keep going with the rest.
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nearby Networks',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _scanning ? null : _scan),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Check off any networks you want to add, then tap Add Selected.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              if (_scanning)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  ),
                )
              else if (_results.isEmpty)
                const Expanded(child: Center(child: Text('No networks found.')))
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final ap = _results[i];
                      final name = ap.ssid.isNotEmpty ? ap.ssid : '(hidden network)';
                      return CheckboxListTile(
                        value: _selectedBssids.contains(ap.bssid),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedBssids.add(ap.bssid);
                          } else {
                            _selectedBssids.remove(ap.bssid);
                          }
                        }),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(ap.bssid),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_selectedBssids.isEmpty || _adding) ? null : _addSelected,
                  child: _adding
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Add Selected (${_selectedBssids.length})'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Reads the admin's own phone GPS so they never have to know or type a
/// latitude/longitude themselves — mirrors _AddRouterSheet's "read whatever
/// this phone is connected to" pattern, just for location instead of Wi-Fi.
class _AddLocationSheet extends StatefulWidget {
  const _AddLocationSheet();

  @override
  State<_AddLocationSheet> createState() => _AddLocationSheetState();
}

class _AddLocationSheetState extends State<_AddLocationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _radius = TextEditingController(text: '150');
  bool _detecting = true;
  bool _busy = false;
  String? _error;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    _name.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _error = null;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() {
          _detecting = false;
          _error = 'Location permission is needed to read this phone\'s GPS position. Please allow it, then try again.';
        });
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _detecting = false;
          _error = 'Location is turned off on this phone. Turn it on, then try again.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      setState(() {
        _detecting = false;
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detecting = false;
        _error = kIsWeb
            ? 'Browser location is unavailable. Allow location for this site or choose a point on the map.'
            : 'Could not read this phone\'s current location. Please try again.';
      });
    }
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<ll.LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialLatitude: _latitude, initialLongitude: _longitude),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _latitude = picked.latitude;
        _longitude = picked.longitude;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_latitude == null || _longitude == null || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppProvider>().adminApiService.addLocation(
        name: _name.text.trim(),
        latitude: _latitude!,
        longitude: _longitude!,
        radiusMeters: double.tryParse(_radius.text.trim()) ?? 150,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add This Location',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Stand at the office, then add it — nothing technical to type.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          if (_detecting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: _detect, child: const Text('Try Again')),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _pickOnMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Pick on Map Instead'),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.my_location_rounded, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Position: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickOnMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Adjust on Map'),
              ),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name (so you recognize it later)'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _radius,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Radius (meters)',
                      helperText: '150m is a reasonable default for ordinary GPS drift.',
                    ),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n < 20 || n > 2000) {
                        return 'Enter a number between 20 and 2000';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Add This Location'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
