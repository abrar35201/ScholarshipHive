using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Data;

public static class DbSeeder
{
    public static async Task SeedAsync(AppDbContext db, IPasswordHasher<User> hasher, IConfiguration configuration)
    {
        if (!await db.Users.AnyAsync())
        {
            var bootstrapPassword = configuration["Bootstrap:AdminPassword"];
            if (string.IsNullOrWhiteSpace(bootstrapPassword) || bootstrapPassword.Length < 12)
                throw new InvalidOperationException("Empty PostgreSQL database: set Bootstrap:AdminPassword (at least 12 chars) in user-secrets or a deployment secret before first startup. Never use a built-in default.");
            var admin = new User
            {
                Username = "admin",
                FullName = "Administrator",
                Role = UserRole.Admin,
                IsActive = true
            };
            admin.PasswordHash = hasher.HashPassword(admin, bootstrapPassword);
            db.Users.Add(admin);
        }

        // A dedicated, low-privilege account for the Play Console "App access"
        // credentials field — kept separate from any real employee's login so
        // nobody's actual password ever has to be shared for review purposes.
        // Still subject to the same geofence login check as everyone else (see
        // AuthController.Login), which is expected and explained in the App
        // access instructions text, not a bug to work around here.
        var reviewPassword = configuration["Bootstrap:ReviewerPassword"];
        if (!string.IsNullOrWhiteSpace(reviewPassword) && reviewPassword.Length >= 12 &&
            !await db.Users.AnyAsync(u => u.Username == "playstore_reviewer"))
        {
            var reviewer = new User
            {
                Username = "playstore_reviewer",
                FullName = "Play Store Reviewer",
                Role = UserRole.Employee,
                Department = EmployeeDepartment.Others,
                IsActive = true,
                IsApproved = true
            };
            reviewer.PasswordHash = hasher.HashPassword(reviewer, reviewPassword);
            db.Users.Add(reviewer);
        }

        if (!db.AllowedRouters.Any())
        {
            db.AllowedRouters.Add(new AllowedRouter
            {
                Name = "Office Router (update me)",
                Bssid = "00:00:00:00:00:00",
                IsActive = false
            });
        }

        await db.SaveChangesAsync();
    }
}
