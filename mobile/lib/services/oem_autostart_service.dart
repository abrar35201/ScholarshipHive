import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _shownKey = 'oem_autostart_guide_shown';

/// Several major Android skins (Xiaomi/MIUI, Vivo, Oppo/Realme, Huawei, Asus,
/// Samsung, OnePlus, and the Transsion family — Infinix/Tecno/itel, extremely
/// common budget brands) run their OWN battery/autostart manager on top of
/// Android's standard one — killing background services like the attendance
/// monitor even after the normal "ignore battery optimizations" permission is
/// granted. There's no way to detect or fix this programmatically; the best
/// available option is guiding the user to that phone's own extra settings
/// screen once, right after they first log in.
class OemAutostartService {
  /// Manufacturer strings as reported by device_info_plus, lowercased.
  /// Populated once the OEM intents are verified — see OemAutostartInfo.
  static const Set<String> _knownAggressiveManufacturers = {
    'xiaomi',
    'redmi',
    'poco',
    'vivo',
    'iqoo',
    'oppo',
    'realme',
    'huawei',
    'honor',
    'asus',
    'samsung',
    'oneplus',
    'infinix',
    'tecno',
    'itel',
  };

  static Future<String?> detectManufacturer() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.manufacturer.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// Whether this phone's manufacturer is one known to need the extra
  /// OEM-specific autostart step, regardless of whether it's been shown yet.
  static Future<bool> isAggressiveOem() async {
    final manufacturer = await detectManufacturer();
    if (manufacturer == null) return false;
    return _knownAggressiveManufacturers.any((m) => manufacturer.contains(m));
  }

  static Future<bool> isGuideMarkedShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_shownKey) == true;
  }

  static Future<void> markGuideShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shownKey, true);
  }
}
