namespace ScholarshipHive.Server.Services;

public static class AuthPolicy
{
    public const int MaxFailedAttempts = 5;
    public static readonly TimeSpan LockoutDuration = TimeSpan.FromMinutes(15);
}
