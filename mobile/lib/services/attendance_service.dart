import '../core/api_config.dart';
import '../models/attendance_day.dart';
import 'api_client.dart';

class AttendanceService {
  final ApiClient _api;
  AttendanceService(this._api);

  /// Own attendance for the last month, Present/Absent only.
  Future<List<AttendanceDay>> mine() async {
    final result = await _api.getList(ApiConfig.myAttendance);
    return result.map((e) => AttendanceDay.fromJson(e as Map<String, dynamic>)).toList();
  }
}
