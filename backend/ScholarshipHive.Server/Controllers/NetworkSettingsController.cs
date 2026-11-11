using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy = "AdminOnlyStrict")]
public class NetworkSettingsController : Controller
{
    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _realtime;

    public NetworkSettingsController(AppDbContext db, RealtimeNotifier realtime)
    {
        _db = db;
        _realtime = realtime;
    }

    public Task<IActionResult> Index() => RenderIndexAsync();

    private async Task<IActionResult> RenderIndexAsync(RouterFormViewModel? routerForm = null, bool showAddRouterModal = false)
    {
        var routers = await _db.AllowedRouters.OrderByDescending(r => r.CreatedAt).ToListAsync();
        ViewBag.PendingNetworks = await _db.PendingNetworks.OrderByDescending(p => p.LastSeenAt).ToListAsync();
        ViewBag.Locations = await _db.AllowedLocations.OrderByDescending(l => l.CreatedAt).ToListAsync();
        ViewBag.RouterFormModel = routerForm ?? new RouterFormViewModel();
        ViewBag.ShowAddRouterModal = showAddRouterModal;
        return View(routers);
    }

    [HttpGet]
    public IActionResult Create() => RedirectToAction(nameof(Index));

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Create(RouterFormViewModel model)
    {
        if (ModelState.IsValid)
        {
            var bssid = NetworkAccessService.Normalize(model.Bssid);
            var existingBssids = await _db.AllowedRouters.Select(r => r.Bssid).ToListAsync();
            if (existingBssids.Any(existing => NetworkAccessService.Normalize(existing) == bssid))
            {
                ModelState.AddModelError(nameof(model.Bssid), "This BSSID is already added.");
            }
            else
            {
                _db.AllowedRouters.Add(new AllowedRouter
                {
                    Name = model.Name.Trim(),
                    Bssid = bssid,
                    IsActive = model.IsActive
                });
                await _db.SaveChangesAsync();
                await _realtime.NotifyAsync("network");
                TempData["Success"] = $"Router \"{model.Name.Trim()}\" added.";
                return RedirectToAction(nameof(Index));
            }
        }

        model.Bssid = NetworkAccessService.Normalize(model.Bssid);
        TempData["Error"] = "Router was not saved. Check the BSSID format and any duplicate router notice in the form.";
        return await RenderIndexAsync(model, showAddRouterModal: true);
    }

    // ----- Geofenced locations ----- wakes the mobile app's attendance
    // service on arrival/departure; AllowedRouter above stays the actual
    // attendance verification.

    public async Task<IActionResult> CreateLocation()
    {
        await SetMapContextAsync();
        return View(new LocationFormViewModel());
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> CreateLocation(LocationFormViewModel model)
    {
        if (!ModelState.IsValid)
        {
            await SetMapContextAsync();
            return View(model);
        }

        _db.AllowedLocations.Add(new AllowedLocation
        {
            Name = model.Name,
            Latitude = model.Latitude,
            Longitude = model.Longitude,
            RadiusMeters = model.RadiusMeters,
            IsActive = model.IsActive
        });
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("network");
        TempData["Success"] = $"Location \"{model.Name}\" added.";
        return RedirectToAction(nameof(Index));
    }

    public async Task<IActionResult> EditLocation(int id)
    {
        var location = await _db.AllowedLocations.FindAsync(id);
        if (location is null) return NotFound();

        await SetMapContextAsync(excludeId: id);
        return View(new LocationFormViewModel
        {
            Id = location.Id,
            Name = location.Name,
            Latitude = location.Latitude,
            Longitude = location.Longitude,
            RadiusMeters = location.RadiusMeters,
            IsActive = location.IsActive
        });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> EditLocation(LocationFormViewModel model)
    {
        var location = await _db.AllowedLocations.FindAsync(model.Id);
        if (location is null) return NotFound();

        if (!ModelState.IsValid)
        {
            await SetMapContextAsync(excludeId: model.Id);
            return View(model);
        }

        location.Name = model.Name;
        location.Latitude = model.Latitude;
        location.Longitude = model.Longitude;
        location.RadiusMeters = model.RadiusMeters;
        location.IsActive = model.IsActive;

        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("network");
        TempData["Success"] = "Location updated successfully.";
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> DeleteLocation(int id)
    {
        var location = await _db.AllowedLocations.FindAsync(id);
        if (location is not null)
        {
            _db.AllowedLocations.Remove(location);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("network");
            TempData["Success"] = "Location removed.";
        }
        return RedirectToAction(nameof(Index));
    }

    /// Feeds the map picker partial something far more precise to open on than
    /// a whole-country view: the most recently added existing location (if
    /// any) as the initial center/zoom, plus every OTHER existing location as
    /// reference markers so a new pin can be placed relative to real ones —
    /// instead of the previous flat "center of Pakistan, zoom 5" fallback,
    /// which needed several manual zoom-ins before a click could land
    /// anywhere near the right spot.
    private async Task SetMapContextAsync(int? excludeId = null)
    {
        var locations = await _db.AllowedLocations
            .Where(l => excludeId == null || l.Id != excludeId)
            .OrderByDescending(l => l.CreatedAt)
            .ToListAsync();

        ViewBag.ExistingLocations = locations
            .Select(l => new { name = l.Name, latitude = l.Latitude, longitude = l.Longitude })
            .ToList();
        ViewBag.DefaultCenter = locations.Count > 0
            ? new { lat = locations[0].Latitude, lng = locations[0].Longitude }
            : null;
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> ApprovePendingNetwork(int id)
    {
        var pending = await _db.PendingNetworks.FindAsync(id);
        if (pending is not null)
        {
            var bssid = NetworkAccessService.Normalize(pending.Bssid);
            var existingBssids = await _db.AllowedRouters.Select(r => r.Bssid).ToListAsync();
            if (!existingBssids.Any(existing => NetworkAccessService.Normalize(existing) == bssid))
            {
                _db.AllowedRouters.Add(new AllowedRouter
                {
                    Name = string.IsNullOrWhiteSpace(pending.Ssid) ? bssid : pending.Ssid,
                    Bssid = bssid,
                    IsActive = true
                });
            }
            _db.PendingNetworks.Remove(pending);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("network");
            TempData["Success"] = $"Approved \"{pending.Ssid ?? pending.Bssid}\" — it can now be used to check in.";
        }
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> DismissPendingNetwork(int id)
    {
        var pending = await _db.PendingNetworks.FindAsync(id);
        if (pending is not null)
        {
            _db.PendingNetworks.Remove(pending);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("network");
            TempData["Success"] = "Dismissed.";
        }
        return RedirectToAction(nameof(Index));
    }

    public async Task<IActionResult> Edit(int id)
    {
        var router = await _db.AllowedRouters.FindAsync(id);
        if (router is null) return NotFound();

        return View(new RouterFormViewModel
        {
            Id = router.Id,
            Name = router.Name,
            Bssid = router.Bssid,
            IsActive = router.IsActive
        });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Edit(RouterFormViewModel model)
    {
        var router = await _db.AllowedRouters.FindAsync(model.Id);
        if (router is null) return NotFound();

        if (ModelState.IsValid)
        {
            var bssid = NetworkAccessService.Normalize(model.Bssid);
            var existingBssids = await _db.AllowedRouters
                .Where(r => r.Id != router.Id)
                .Select(r => r.Bssid)
                .ToListAsync();
            if (existingBssids.Any(existing => NetworkAccessService.Normalize(existing) == bssid))
            {
                ModelState.AddModelError(nameof(model.Bssid), "This BSSID is already added.");
            }
            else
            {
                router.Name = model.Name.Trim();
                router.Bssid = bssid;
                router.IsActive = model.IsActive;

                await _db.SaveChangesAsync();
                await _realtime.NotifyAsync("network");
                TempData["Success"] = "Router updated successfully.";
                return RedirectToAction(nameof(Index));
            }
        }

        model.Bssid = NetworkAccessService.Normalize(model.Bssid);
        return View(model);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(int id)
    {
        var router = await _db.AllowedRouters.FindAsync(id);
        if (router is not null)
        {
            _db.AllowedRouters.Remove(router);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("network");
            TempData["Success"] = "Router removed.";
        }
        return RedirectToAction(nameof(Index));
    }

}
