using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Services;

public class NetworkAccessResult
{
    public bool Allowed { get; init; }
    public string Message { get; init; } = string.Empty;
}

public class NetworkAccessService
{
    private readonly AppDbContext _db;

    public NetworkAccessService(AppDbContext db)
    {
        _db = db;
    }

    public static string Normalize(string bssid) =>
        bssid.Trim().Replace("-", ":").ToUpperInvariant();

    /// A normalized-BSSID -> router name lookup, for showing an admin "Office Router"
    /// instead of a bare MAC address wherever a BSSID would otherwise be displayed.
    /// Includes inactive routers too, since old history can reference one that was
    /// later deactivated — falling back to "Unknown Router" only if it's gone entirely
    /// (e.g. deleted) is handled by the caller.
    public async Task<Dictionary<string, string>> GetRouterNameLookupAsync()
    {
        var routers = await _db.AllowedRouters.ToListAsync();
        var lookup = new Dictionary<string, string>();
        foreach (var r in routers)
        {
            lookup[Normalize(r.Bssid)] = r.Name;
        }
        return lookup;
    }

    /// Authenticates purely on "is this BSSID in the approved list" — no subnet/IP
    /// cross-check, since employees connect from many different physical locations
    /// (each with their own router and subnet) that the admin can't pre-verify from
    /// their own laptop. callerIp/ssid are recorded for the pending-network log only.
    ///
    /// `insideGeofence` gates whether an unrecognized network even gets logged as
    /// pending at all — before this, ANY unrecognized Wi-Fi a phone happened to be on
    /// (someone's home network, a hostel, a random shop) landed in the admin's Pending
    /// Networks list, since it had nothing to do with whether the device was actually
    /// anywhere near the office. Only a router seen while the device was confirmed
    /// inside an approved GPS geofence is worth an admin's attention now. Pass null
    /// when location isn't known at this call site at all (e.g. the anonymous
    /// check-network/register calls, which carry no coordinates) — that's treated the
    /// same as "not confirmed inside," so nothing gets recorded rather than guessing.
    public async Task<NetworkAccessResult> CheckAsync(string? deviceBssid, string? callerIp, string? ssid = null, bool? insideGeofence = null)
    {
        var activeRouters = await _db.AllowedRouters.Where(r => r.IsActive).ToListAsync();

        if (string.IsNullOrWhiteSpace(deviceBssid))
        {
            return new NetworkAccessResult
            {
                Allowed = false,
                Message = "Could not detect your Wi-Fi network. Make sure Wi-Fi and Location are turned on, then try again."
            };
        }

        var normalizedDevice = Normalize(deviceBssid);
        var matchedRouter = activeRouters.FirstOrDefault(r => Normalize(r.Bssid) == normalizedDevice);

        if (matchedRouter is not null)
        {
            return new NetworkAccessResult { Allowed = true, Message = "Network verified." };
        }

        if (insideGeofence == true)
        {
            await RecordPendingNetworkAsync(normalizedDevice, ssid, callerIp);
        }

        if (activeRouters.Count == 0)
        {
            return new NetworkAccessResult
            {
                Allowed = false,
                Message = "No approved router has been configured yet. Please contact your administrator."
            };
        }

        return new NetworkAccessResult
        {
            Allowed = false,
            Message = "This device is not connected to an approved network. Please check your Wi-Fi connection, or ask your administrator to approve this network."
        };
    }

    /// Logs an unrecognized BSSID so the admin can approve it from the Pending Networks
    /// list with one click, instead of needing to physically scan it from their own laptop.
    private async Task RecordPendingNetworkAsync(string normalizedBssid, string? ssid, string? callerIp)
    {
        var pending = await _db.PendingNetworks.FirstOrDefaultAsync(p => p.Bssid == normalizedBssid);
        var now = DateTime.UtcNow;

        if (pending is null)
        {
            _db.PendingNetworks.Add(new PendingNetwork
            {
                Bssid = normalizedBssid,
                Ssid = string.IsNullOrWhiteSpace(ssid) ? null : ssid.Trim(),
                LastSeenFromIp = callerIp,
                AttemptCount = 1,
                FirstSeenAt = now,
                LastSeenAt = now
            });
        }
        else
        {
            pending.AttemptCount++;
            pending.LastSeenAt = now;
            pending.LastSeenFromIp = callerIp;
            if (string.IsNullOrWhiteSpace(pending.Ssid) && !string.IsNullOrWhiteSpace(ssid))
            {
                pending.Ssid = ssid.Trim();
            }
        }

        await _db.SaveChangesAsync();
    }
}
