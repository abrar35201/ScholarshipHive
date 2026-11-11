using Microsoft.AspNetCore.SignalR;
using ScholarshipHive.Server.Hubs;

namespace ScholarshipHive.Server.Services;

/// Thin wrapper so controllers can broadcast "something changed" without depending
/// directly on IHubContext's generic-heavy API. Category is informational only —
/// clients simply refetch whatever they're currently showing on any event.
public class RealtimeNotifier
{
    private readonly IHubContext<AttendanceHub> _hub;

    public RealtimeNotifier(IHubContext<AttendanceHub> hub)
    {
        _hub = hub;
    }

    public Task NotifyAsync(string category) =>
        _hub.Clients.All.SendAsync("DataChanged", category);
}
