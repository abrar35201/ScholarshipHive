using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

public class AccountController : Controller
{
    private readonly AppDbContext _db;
    private readonly IPasswordHasher<User> _hasher;

    public AccountController(AppDbContext db, IPasswordHasher<User> hasher)
    {
        _db = db;
        _hasher = hasher;
    }

    [HttpGet]
    [AllowAnonymous]
    public async Task<IActionResult> Login()
    {
        if (User.Identity?.IsAuthenticated == true)
        {
            if (User.IsInRole("Employee")) return RedirectToAction("Mine", "ShiftRequests");
            if (User.IsInRole("Receptionist")) return RedirectToAction("Index", "Reception");
            if (User.IsInRole("Auditor")) return RedirectToAction("Index", "ActivityLog");
            if ((User.IsInRole("HeadOfCounselors") || User.IsInRole("HeadOfMarketing") || User.IsInRole("HeadOfProcessing"))) return RedirectToAction("Index", "TeamScope");
            if (User.IsInRole("Admin") || User.IsInRole("Auditor") || User.IsInRole("SuperAdmin") || User.IsInRole("Owner") || User.IsInRole("CountryHead") || User.IsInRole("HeadOfMarketing") || User.IsInRole("HeadOfProcessing"))
            {
                return RedirectToAction("Index", "Home");
            }
            // Stale Employee cookie from before web access was restricted to Admins/Auditors.
            await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
        }
        return View(new LoginViewModel());
    }

    [HttpPost]
    [AllowAnonymous]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Login(LoginViewModel model)
    {
        if (!ModelState.IsValid)
        {
            return View(model);
        }

        // Employees receive a narrowly scoped web session for their own shift requests.
        var normalizedUsername = model.Username.Trim().ToLowerInvariant();
        var user = await _db.Users.FirstOrDefaultAsync(u =>
            u.Username.ToLower() == normalizedUsername && u.IsActive);

        if (user is null)
        {
            model.Error = "Invalid username or password.";
            return View(model);
        }

        if (user.LockedUntil is not null && user.LockedUntil > DateTime.UtcNow)
        {
            var minutesLeft = Math.Ceiling((user.LockedUntil.Value - DateTime.UtcNow).TotalMinutes);
            model.Error = $"Too many failed attempts. Try again in {minutesLeft} minute(s).";
            return View(model);
        }

        if (_hasher.VerifyHashedPassword(user, user.PasswordHash, model.Password) == PasswordVerificationResult.Failed)
        {
            user.FailedLoginAttempts++;
            if (user.FailedLoginAttempts >= AuthPolicy.MaxFailedAttempts)
            {
                user.LockedUntil = DateTime.UtcNow.Add(AuthPolicy.LockoutDuration);
                user.FailedLoginAttempts = 0;
            }
            await _db.SaveChangesAsync();

            model.Error = "Invalid username or password.";
            return View(model);
        }

        if (!user.IsApproved)
        {
            model.Error = "This account is still pending admin approval.";
            return View(model);
        }

        if (user.Role != UserRole.Employee && !AccessRules.IsBroadManager(user.Role) && user.Role is not (UserRole.HeadOfProcessing or UserRole.HeadOfCounselors or UserRole.HeadOfMarketing or UserRole.Receptionist))
        {
            model.Error = "This web portal is for administrators only. Please use the ScholarshipHive mobile app instead.";
            return View(model);
        }

        user.FailedLoginAttempts = 0;
        user.LockedUntil = null;
        await _db.SaveChangesAsync();

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.Username),
            new(ClaimTypes.Role, user.Role.ToString())
        };

        var identity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
        await HttpContext.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, new ClaimsPrincipal(identity));

        return user.Role == UserRole.Employee ? RedirectToAction("Mine", "ShiftRequests") : RedirectToAction("Index", user.Role == UserRole.Receptionist ? "Reception" :
            user.Role == UserRole.Auditor ? "ActivityLog" :
            AccessRules.IsDepartmentHead(user.Role) ? "TeamScope" : "Home");
    }

    [HttpPost]
    [Authorize]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Logout()
    {
        await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
        return RedirectToAction("Login");
    }

    [AllowAnonymous]
    public IActionResult AccessDenied() => View();
}
