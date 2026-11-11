/// Shared form validators — kept in one place so every password field (register,
/// change password, admin create/edit user) enforces the same rule as the
/// backend's StrongPasswordAttribute, instead of drifting out of sync.
class Validators {
  static String? strongPassword(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    if (value.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Add an uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(value)) return 'Add a lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Add a number';
    if (!RegExp(r'[^a-zA-Z0-9]').hasMatch(value)) return 'Add a special character';
    return null;
  }

  /// For "leave blank to keep the current password" fields — only enforces
  /// strength when something was actually typed.
  static String? optionalStrongPassword(String? value) {
    if (value == null || value.isEmpty) return null;
    return strongPassword(value);
  }
}
