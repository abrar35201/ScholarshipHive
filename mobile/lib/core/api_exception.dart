class ApiException implements Exception {
  final String message;
  final int? statusCode;
  /// Machine-readable reason from the server's ApiError.Code, if it sent one —
  /// lets callers branch on specific cases (e.g. "location_not_confirmed")
  /// without string-matching the display message.
  final String? code;
  ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}
