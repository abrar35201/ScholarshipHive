import '../core/api_config.dart';
import '../core/department_utils.dart';
import '../models/admin_models.dart';
import 'api_client.dart';

int _roleToInt(String role) => switch (role) {
  'Admin' => 1,
  'Auditor' => 2,
  'Receptionist' => 3,
  'Owner' => 5,
  'CountryHead' => 6,
  'HeadOfMarketing' => 7,
  'HeadOfProcessing' => 8,
  'HeadOfCounselors' => 9,
  _ => 0,
};

class AdminApiService {
  final ApiClient _api;
  AdminApiService(this._api);

  Future<AdminDashboard> dashboard({String period = 'day'}) async {
    final uri = Uri.parse(
      ApiConfig.adminDashboard,
    ).replace(queryParameters: {'period': period});
    final result = await _api.get(uri.toString());
    return AdminDashboard.fromJson(result);
  }

  Future<AnalyticsData> analytics() async {
    final result = await _api.get(ApiConfig.adminAnalytics);
    return AnalyticsData.fromJson(result);
  }

  Future<List<TeamMetricsEntry>> teamMetrics() async {
    final result = await _api.getList(ApiConfig.adminTeamMetrics);
    return result
        .map((e) => TeamMetricsEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<OfficeAttendance> officeAttendance({
    DateTime? date,
    String? department,
  }) async {
    final query = <String, String>{
      if (date != null) 'date': _dateStr(date),
      if (department != null) 'department': department,
    };
    final uri = Uri.parse(
      ApiConfig.adminOfficeAttendance,
    ).replace(queryParameters: query.isEmpty ? null : query);
    final result = await _api.get(uri.toString());
    return OfficeAttendance.fromJson(result);
  }

  Future<List<AdminUser>> users() async {
    final result = await _api.getList(ApiConfig.adminUsers);
    return result
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createUser({
    required String username,
    required String fullName,
    required String password,
    required String role,
    String department = 'Calling',
  }) => _api.post(ApiConfig.adminUsers, {
    'username': username,
    'fullName': fullName,
    'password': password,
    'role': _roleToInt(role),
    'department': departmentToInt(department),
  });

  Future<void> editUser({
    required int id,
    required String username,
    required String fullName,
    String? password,
    required String role,
    required bool isActive,
    required bool isApproved,
    String department = 'Calling',
  }) => _api.put('${ApiConfig.adminUsers}/$id', {
    'username': username,
    'fullName': fullName,
    if (password != null && password.isNotEmpty) 'password': password,
    'role': _roleToInt(role),
    'department': departmentToInt(department),
    'isActive': isActive,
    'isApproved': isApproved,
  });

  Future<void> approveUser(int id) =>
      _api.post('${ApiConfig.adminUsers}/$id/approve', {});

  Future<AdminUserDetail> userDetail(int id) async {
    final result = await _api.get('${ApiConfig.adminUsers}/$id/detail');
    return AdminUserDetail.fromJson(result);
  }

  Future<void> deleteUser(int id) => _api.delete('${ApiConfig.adminUsers}/$id');

  Future<void> setMarketingAdmin(int id, bool enabled) =>
      _api.post('${ApiConfig.adminUsers}/$id/marketing-admin', {'enabled': enabled});

  /// One person's shift — [startTime]/[endTime] as "HH:mm", [shiftType] as
  /// 'Day', 'Night', or 'Internship'.
  Future<void> setShift({
    required int userId,
    required String startTime,
    required String endTime,
    required String shiftType,
  }) => _api.put('${ApiConfig.adminUsers}/$userId/shift', {
    'shiftStartTime': startTime,
    'shiftEndTime': endTime,
    'shiftType': shiftTypeToInt(shiftType),
  });

  /// Bulk-apply a shift — either every employee in [department], or (when
  /// [userIds] is non-empty) exactly those people regardless of department.
  Future<void> setShiftBulk({
    List<int> userIds = const [],
    String? department,
    required String startTime,
    required String endTime,
    required String shiftType,
  }) => _api.post('${ApiConfig.adminUsers}/shift/bulk', {
    'userIds': userIds,
    if (department != null) 'department': departmentToInt(department),
    'shiftStartTime': startTime,
    'shiftEndTime': endTime,
    'shiftType': shiftTypeToInt(shiftType),
  });

  Future<List<AdminAttendance>> attendance({int? userId}) async {
    final uri = Uri.parse(ApiConfig.adminAttendance).replace(
      queryParameters: userId != null ? {'userId': userId.toString()} : null,
    );
    final result = await _api.getList(uri.toString());
    return result
        .map((e) => AdminAttendance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Omitting both dates defaults to today (server-side); omitting only one
  /// treats the range as that single day.
  Future<List<AdminReport>> reports({
    int? userId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final query = <String, String>{
      if (userId != null) 'userId': userId.toString(),
      if (fromDate != null) 'fromDate': _dateStr(fromDate),
      if (toDate != null) 'toDate': _dateStr(toDate),
    };
    final uri = Uri.parse(
      ApiConfig.adminReports,
    ).replace(queryParameters: query.isEmpty ? null : query);
    final result = await _api.getList(uri.toString());
    return result
        .map((e) => AdminReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<int>> downloadReportFile(int fileId) =>
      _api.getBytes(ApiConfig.adminReportFile(fileId));

  Future<void> signOffReport(int id) =>
      _api.post(ApiConfig.adminReportSignOff(id), {});
  Future<void> flagReport(int id) =>
      _api.post(ApiConfig.adminReportFlag(id), {});
  Future<void> askForDetailReport(int id) =>
      _api.post(ApiConfig.adminReportAskForDetail(id), {});

  Future<List<AdminRouter>> routers() async {
    final result = await _api.getList(ApiConfig.adminRouters);
    return result
        .map((e) => AdminRouter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addRouter({required String name, required String bssid}) =>
      _api.post(ApiConfig.adminRouters, {
        'name': name,
        'bssid': bssid,
        'isActive': true,
      });

  Future<void> toggleRouterActive(AdminRouter router) => _api.put(
    '${ApiConfig.adminRouters}/${router.id}',
    {'name': router.name, 'bssid': router.bssid, 'isActive': !router.isActive},
  );

  Future<void> deleteRouter(int id) =>
      _api.delete('${ApiConfig.adminRouters}/$id');

  Future<List<AdminLocation>> locations() async {
    final result = await _api.getList(ApiConfig.adminLocations);
    return result
        .map((e) => AdminLocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addLocation({
    required String name,
    required double latitude,
    required double longitude,
    double radiusMeters = 150,
  }) => _api.post(ApiConfig.adminLocations, {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    'isActive': true,
  });

  Future<void> toggleLocationActive(AdminLocation l) =>
      _api.put('${ApiConfig.adminLocations}/${l.id}', {
        'name': l.name,
        'latitude': l.latitude,
        'longitude': l.longitude,
        'radiusMeters': l.radiusMeters,
        'isActive': !l.isActive,
      });

  Future<void> deleteLocation(int id) =>
      _api.delete('${ApiConfig.adminLocations}/$id');

  Future<List<AdminPendingNetwork>> pendingNetworks() async {
    final result = await _api.getList(ApiConfig.adminPendingNetworks);
    return result
        .map((e) => AdminPendingNetwork.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approvePendingNetwork(int id) =>
      _api.post('${ApiConfig.adminPendingNetworks}/$id/approve', {});

  Future<void> dismissPendingNetwork(int id) =>
      _api.delete('${ApiConfig.adminPendingNetworks}/$id');

  /// Every active employee's total accumulated presence over [from, to] —
  /// omitting either bound defaults server-side to the last calendar month
  /// through today.
  Future<List<HoursListEntry>> hours({DateTime? from, DateTime? to}) async {
    final query = <String, String>{
      if (from != null) 'from': _dateStr(from),
      if (to != null) 'to': _dateStr(to),
    };
    final uri = Uri.parse(
      ApiConfig.adminHours,
    ).replace(queryParameters: query.isEmpty ? null : query);
    final result = await _api.getList(uri.toString());
    return result
        .map((e) => HoursListEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// One person's day-by-day breakdown — an explicit range here overrides
  /// whatever default/global range the list page was showing.
  Future<HoursDetail> hoursDetail(int userId, {DateTime? from, DateTime? to}) async {
    final query = <String, String>{
      if (from != null) 'from': _dateStr(from),
      if (to != null) 'to': _dateStr(to),
    };
    final uri = Uri.parse(
      ApiConfig.adminHoursDetail(userId),
    ).replace(queryParameters: query.isEmpty ? null : query);
    final result = await _api.get(uri.toString());
    return HoursDetail.fromJson(result);
  }

  Future<List<PendingPasswordResetEntry>> passwordResets() async {
    final result = await _api.getList(ApiConfig.adminPasswordResets);
    return result
        .map((e) => PendingPasswordResetEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approvePasswordReset(int id) =>
      _api.post('${ApiConfig.adminPasswordResets}/$id/approve', {});

  Future<void> rejectPasswordReset(int id) =>
      _api.post('${ApiConfig.adminPasswordResets}/$id/reject', {});
}
