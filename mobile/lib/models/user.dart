class AppUser {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final String department;
  final String shiftStartTime;
  final String shiftEndTime;

  AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.department,
    this.shiftStartTime = '09:30:00',
    this.shiftEndTime = '17:30:00',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        username: json['username'] as String,
        fullName: json['fullName'] as String? ?? '',
        role: json['role'] as String? ?? 'Employee',
        department: json['department'] as String? ?? 'Calling',
        shiftStartTime: json['shiftStartTime'] as String? ?? '09:30:00',
        shiftEndTime: json['shiftEndTime'] as String? ?? '17:30:00',
      );
}
