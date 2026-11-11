/// One day of an employee's own attendance history — Present/Absent(/Late/
/// Extra/Weekend) only. Exact check-in/check-out timings are an
/// Admin/Auditor-only view.
class AttendanceDay {
  final String date;
  final bool present;

  /// 'Present' | 'Late' | 'Absent' | 'Extra' | 'Weekend'.
  final String status;

  AttendanceDay({required this.date, required this.present, required this.status});

  factory AttendanceDay.fromJson(Map<String, dynamic> json) => AttendanceDay(
        date: json['date'] as String,
        present: json['present'] == true,
        status: json['status'] as String? ?? (json['present'] == true ? 'Present' : 'Absent'),
      );
}
