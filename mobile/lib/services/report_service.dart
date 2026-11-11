import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../core/api_config.dart';
import '../models/report.dart';
import 'api_client.dart';

class ReportService {
  final ApiClient _api;
  ReportService(this._api);

  /// Creates today's report the first time, or updates it on later calls —
  /// only ever affects today's entry. [newFiles] are appended to whatever was
  /// already uploaded today, never replacing them.
  Future<DailyReport> submitReport({
    int unreadChats = 0,
    int newLeads = 0,
    int qualifiedLeads = 0,
    int followUp = 0,
    int calls = 0,
    int potential = 0,
    int walkIns = 0,
    int conversion = 0,
    String? textContent,
    List<PlatformFile> newFiles = const [],
  }) async {
    final form = FormData.fromMap({
      'unreadChats': unreadChats,
      'newLeads': newLeads,
      'qualifiedLeads': qualifiedLeads,
      'followUp': followUp,
      'calls': calls,
      'potential': potential,
      'walkIns': walkIns,
      'conversion': conversion,
      if (textContent != null) 'textContent': textContent,
      'files': [for (final f in newFiles) MultipartFile.fromBytes(f.bytes!, filename: f.name)],
    });
    final result = await _api.postMultipart(ApiConfig.submitReport, form);
    return DailyReport.fromJson(result);
  }

  Future<List<DailyReport>> myReports() async {
    final result = await _api.getList(ApiConfig.myReports);
    return result.map((e) => DailyReport.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<int>> downloadMyReportFile(int fileId) => _api.getBytes(ApiConfig.reportFile(fileId));
}
