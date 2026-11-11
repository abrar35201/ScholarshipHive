using System.Net.Mail;
using System.Text.RegularExpressions;

namespace ScholarshipHive.Server.Services;

/// <summary>Validates reception visitor details at the server boundary.</summary>
public static class VisitorInputRules
{
    private static readonly Regex NamePattern = new(@"^[\p{L}][\p{L}\p{M} .'-]{1,119}$", RegexOptions.Compiled);
    private static readonly Regex PhonePattern = new(@"^\+?[0-9]{7,15}$", RegexOptions.Compiled);

    public static string? Error(string? name, string? contact, string? email)
    {
        if (string.IsNullOrWhiteSpace(name) || !NamePattern.IsMatch(name.Trim()))
            return "Enter a valid visitor name (letters and spaces, 2–120 characters).";
        var phone = (contact ?? "").Replace(" ", "").Replace("-", "");
        if (!PhonePattern.IsMatch(phone))
            return "Enter a valid contact number (7–15 digits, optional + prefix).";
        if (!string.IsNullOrWhiteSpace(email))
        {
            if (email.Length > 150 || !MailAddress.TryCreate(email.Trim(), out var addr) ||
                !addr.Address.Equals(email.Trim(), StringComparison.OrdinalIgnoreCase) ||
                !addr.Host.Contains('.'))
                return "Enter a valid email address or leave it empty.";
        }
        return null;
    }
}
