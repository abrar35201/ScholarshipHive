using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;

namespace ScholarshipHive.Server.Data;

// Dotnet EF commands must use the same PostgreSQL provider as runtime.
// Design-time operations should not execute app startup seeders/hosted services.
public sealed class PostgresDesignTimeFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var config = new ConfigurationBuilder()
            .SetBasePath(Directory.GetCurrentDirectory())
            .AddJsonFile("appsettings.json", optional: true)
            .AddJsonFile("appsettings.Development.json", optional: true)
            .AddUserSecrets<AppDbContext>(optional: true)
            .AddEnvironmentVariables()
            .Build();
        var connection = config.GetConnectionString("DefaultConnection");
        if (string.IsNullOrWhiteSpace(connection))
            throw new InvalidOperationException("Set ConnectionStrings:DefaultConnection in user-secrets or environment for EF PostgreSQL migrations.");
        return new AppDbContext(
            new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(connection).Options,
            new HttpContextAccessor());
    }
}
