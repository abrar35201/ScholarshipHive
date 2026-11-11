using Microsoft.AspNetCore.Http;

namespace ScholarshipHive.Server.Services;

/// A short blocklist of extensions that can run code on whoever opens them, checked on
/// every report/audit-report file upload. Everything else — any office file type, image,
/// PDF, whatever an employee actually needs to attach — still goes through untouched;
/// this is deliberately not an allowlist, since the product intentionally accepts any
/// ordinary file type.
public static class FileSafety
{
    private static readonly HashSet<string> BlockedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".exe", ".msi", ".bat", ".cmd", ".com", ".scr", ".ps1", ".vbs", ".js", ".jar", ".apk", ".sh"
    };

    public static bool IsDangerous(string? fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName)) return false;
        var ext = Path.GetExtension(fileName);
        return BlockedExtensions.Contains(ext);
    }

    /// Extension-only blocking is trivially bypassed by just renaming the file — this
    /// looks at the actual first few bytes instead, which is what the file really is
    /// regardless of what its name claims. Reading a handful of bytes here doesn't
    /// consume the upload: IFormFile.OpenReadStream() hands back an independent stream
    /// positioned at the start of this file's data every time it's called, so the
    /// caller's own later CopyToAsync still reads the whole file from byte zero.
    public static async Task<bool> HasDangerousContentAsync(IFormFile file)
    {
        var header = new byte[4];
        int read;
        using (var stream = file.OpenReadStream())
        {
            read = await stream.ReadAsync(header.AsMemory(0, header.Length));
        }

        if (read >= 2 && header[0] == 0x4D && header[1] == 0x5A) return true; // "MZ" — Windows EXE/DLL/MSI
        if (read >= 4 && header[0] == 0x7F && header[1] == 0x45 && header[2] == 0x4C && header[3] == 0x46) return true; // ELF (Linux executable)
        if (read >= 2 && header[0] == 0x23 && header[1] == 0x21) return true; // "#!" shebang script
        return false;
    }
}
