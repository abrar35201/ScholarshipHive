import 'report.dart';

/// An Auditor's compiled findings about everyone else's work — separate from
/// the daily per-employee report, which Auditors don't submit at all.
class AuditReport {
  final int id;
  final String auditorUsername;
  final String title;
  final String? textContent;
  final DateTime createdAt;
  final List<ReportFileRef> files;

  AuditReport({
    required this.id,
    required this.auditorUsername,
    required this.title,
    required this.textContent,
    required this.createdAt,
    required this.files,
  });

  factory AuditReport.fromJson(Map<String, dynamic> json) => AuditReport(
        id: json['id'] as int,
        auditorUsername: json['auditorUsername'] as String? ?? '',
        title: json['title'] as String? ?? '',
        textContent: json['textContent'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        files: (json['files'] as List<dynamic>).map((e) => ReportFileRef.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
