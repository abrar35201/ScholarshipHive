import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../core/api_config.dart';
import '../models/audit_report.dart';
import 'api_client.dart';

class AuditReportService {
  final ApiClient _api;
  AuditReportService(this._api);

  /// Auditor-only — submits a brand new audit report each time (unlike the
  /// daily Report, there's no "today's editable entry" concept here).
  Future<AuditReport> submit({
    required String title,
    String? textContent,
    List<PlatformFile> files = const [],
  }) async {
    final form = FormData.fromMap({
      'title': title,
      if (textContent != null) 'textContent': textContent,
      'files': [for (final f in files) MultipartFile.fromBytes(f.bytes!, filename: f.name)],
    });
    final result = await _api.postMultipart(ApiConfig.auditReports, form);
    return AuditReport.fromJson(result);
  }

  Future<List<AuditReport>> list() async {
    final result = await _api.getList(ApiConfig.auditReports);
    return result.map((e) => AuditReport.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<int>> downloadFile(int fileId) => _api.getBytes(ApiConfig.auditReportFile(fileId));
}
