class ReportFileRef {
  final int id;
  final String fileName;
  final DateTime uploadedAt;

  ReportFileRef({required this.id, required this.fileName, required this.uploadedAt});

  factory ReportFileRef.fromJson(Map<String, dynamic> json) => ReportFileRef(
        id: json['id'] as int,
        fileName: json['fileName'] as String,
        uploadedAt: DateTime.parse(json['uploadedAt'] as String),
      );
}

/// One day's KPI report — editable only on the day it's for; a day after, it's
/// read-only history (see [isEditable]).
class DailyReport {
  final int id;
  final String date;
  final int unreadChats;
  final int newLeads;
  final int qualifiedLeads;
  final int followUp;
  final int calls;
  final int potential;
  final int walkIns;
  final int conversion;
  final String? textContent;
  final List<ReportFileRef> files;
  final DateTime submittedAt;
  final DateTime? lastEditedAt;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final bool isEditable;

  DailyReport({
    required this.id,
    required this.date,
    required this.unreadChats,
    required this.newLeads,
    required this.qualifiedLeads,
    required this.followUp,
    required this.calls,
    required this.potential,
    required this.walkIns,
    required this.conversion,
    required this.textContent,
    required this.files,
    required this.submittedAt,
    required this.lastEditedAt,
    required this.checkInTime,
    required this.checkOutTime,
    required this.isEditable,
  });

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
        id: json['id'] as int,
        date: json['date'] as String,
        unreadChats: json['unreadChats'] as int,
        newLeads: json['newLeads'] as int,
        qualifiedLeads: json['qualifiedLeads'] as int,
        followUp: json['followUp'] as int,
        calls: json['calls'] as int,
        potential: json['potential'] as int,
        walkIns: json['walkIns'] as int,
        conversion: json['conversion'] as int,
        textContent: json['textContent'] as String?,
        files: (json['files'] as List<dynamic>).map((e) => ReportFileRef.fromJson(e as Map<String, dynamic>)).toList(),
        submittedAt: DateTime.parse(json['submittedAt'] as String),
        lastEditedAt: json['lastEditedAt'] != null ? DateTime.parse(json['lastEditedAt'] as String) : null,
        checkInTime: DateTime.parse(json['checkInTime'] as String),
        checkOutTime: json['checkOutTime'] != null ? DateTime.parse(json['checkOutTime'] as String) : null,
        isEditable: json['isEditable'] == true,
      );
}
