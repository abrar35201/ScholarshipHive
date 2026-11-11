using System.ComponentModel.DataAnnotations;
using System.Text.RegularExpressions;

namespace ScholarshipHive.Server.Dtos;

/// Requires at least 8 characters with a mix of uppercase, lowercase, a digit,
/// and a special character — applied to every password field (self-registration,
/// admin-created accounts, password changes) so a weak password can't be set
/// anywhere in the app, not just the public registration form.
///
/// Null/empty is treated as valid on purpose: several of these fields are
/// optional "leave blank to keep the current password" fields, and the
/// [Required] attribute (where present) already handles rejecting a genuinely
/// missing value on the fields that need one.
public class StrongPasswordAttribute : ValidationAttribute
{
    private static readonly Regex HasUpper = new("[A-Z]");
    private static readonly Regex HasLower = new("[a-z]");
    private static readonly Regex HasDigit = new("[0-9]");
    private static readonly Regex HasSpecial = new(@"[^a-zA-Z0-9]");

    public StrongPasswordAttribute()
    {
        ErrorMessage = "Password must be at least 8 characters and include an uppercase letter, a lowercase letter, a number, and a special character.";
    }

    public override bool IsValid(object? value)
    {
        if (value is not string password || string.IsNullOrEmpty(password)) return true;

        return password.Length >= 8
            && HasUpper.IsMatch(password)
            && HasLower.IsMatch(password)
            && HasDigit.IsMatch(password)
            && HasSpecial.IsMatch(password);
    }
}
