using Microsoft.Extensions.Caching.Memory;

namespace ScholarshipHive.Server.Services;

/// Backs the kill-switch middleware in Program.cs. Checking IsActive straight
/// from Postgres on every single authenticated request added a DB round-trip
/// to every API call in the app — that's what made login and every screen
/// feel slow. A short TTL keeps that lookup rare, while Invalidate() lets
/// EditUser/etc. still cut a deactivated account off immediately instead of
/// waiting out the TTL.
public class UserActiveStatusCache
{
    private static readonly TimeSpan Ttl = TimeSpan.FromSeconds(60);
    private readonly IMemoryCache _cache;

    public UserActiveStatusCache(IMemoryCache cache)
    {
        _cache = cache;
    }

    private static string Key(int userId) => $"user_active_{userId}";

    public async Task<bool> IsActiveAsync(int userId, Func<Task<bool>> load)
    {
        if (_cache.TryGetValue(Key(userId), out bool cached)) return cached;
        var value = await load();
        _cache.Set(Key(userId), value, Ttl);
        return value;
    }

    public void Invalidate(int userId) => _cache.Remove(Key(userId));
}
