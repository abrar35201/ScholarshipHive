namespace ScholarshipHive.Server.Models;

/// Centralized role/audience rules; all department filters are enforced on the server.
public static class AccessRules
{
    public static string DisplayRole(UserRole role) => role switch {
        UserRole.Admin or UserRole.SuperAdmin => "Administrator",
        UserRole.Owner => "Owner",
        UserRole.CountryHead => "Country Head",
        UserRole.HeadOfMarketing => "Head of Marketing",
        UserRole.HeadOfProcessing => "Head of Processing",
        UserRole.HeadOfCounselors => "Head of Counselors",
        UserRole.Receptionist => "Receptionist",
        UserRole.Employee => "Employee",
        _ => role.ToString()
    };
    public static bool IsOwner(UserRole role) => role is UserRole.Admin or UserRole.Owner or UserRole.SuperAdmin;
    public static bool IsCountryManager(UserRole role) => role == UserRole.CountryHead;
    public static bool IsBroadManager(UserRole role) => IsOwner(role) || IsCountryManager(role) || role == UserRole.Auditor;
    public static bool IsDepartmentHead(UserRole role) => role is UserRole.HeadOfMarketing or UserRole.HeadOfProcessing or UserRole.HeadOfCounselors;
    public static bool IsPrivileged(UserRole role) => role != UserRole.Employee;
    public static bool IsActualEmployeeDepartment(EmployeeDepartment department) =>
        department is EmployeeDepartment.Calling or EmployeeDepartment.Processing or
        EmployeeDepartment.Others or EmployeeDepartment.Interns or EmployeeDepartment.Marketing;
    public static bool CanCreateNotices(UserRole role) => IsOwner(role) || IsCountryManager(role) || IsDepartmentHead(role) || role == UserRole.Receptionist;
    public static EmployeeDepartment? DepartmentScope(UserRole role) => role switch {
        UserRole.HeadOfProcessing => EmployeeDepartment.Processing,
        UserRole.HeadOfCounselors => EmployeeDepartment.Calling,
        UserRole.HeadOfMarketing => EmployeeDepartment.MarketingAndInterns,
        UserRole.Receptionist => EmployeeDepartment.Reception,
        _ => null
    };
    public static bool IsInScope(UserRole role, EmployeeDepartment department) => role switch {
        UserRole.HeadOfMarketing => department is EmployeeDepartment.Marketing or EmployeeDepartment.Interns,
        UserRole.HeadOfProcessing => department == EmployeeDepartment.Processing,
        UserRole.HeadOfCounselors => department == EmployeeDepartment.Calling,
        UserRole.Receptionist => department == EmployeeDepartment.Reception,
        _ => false
    };
    public static bool ReceivesAnnouncement(User user, EmployeeDepartment? audience) =>
        audience is null || IsOwner(user.Role) || IsCountryManager(user.Role) ||
        (audience == EmployeeDepartment.MarketingAndInterns &&
            (user.Department is EmployeeDepartment.Marketing or EmployeeDepartment.Interns || user.Role == UserRole.HeadOfMarketing)) ||
        (audience == EmployeeDepartment.Reception && user.Role == UserRole.Receptionist) ||
        (user.Department == audience && user.Role == UserRole.Employee) ||
        (user.Role == UserRole.HeadOfProcessing && audience == EmployeeDepartment.Processing) ||
        (user.Role == UserRole.HeadOfMarketing && (audience == EmployeeDepartment.Marketing || audience == EmployeeDepartment.Interns)) ||
        (user.Role == UserRole.HeadOfCounselors && audience == EmployeeDepartment.Calling);
    public static bool CanTargetAudience(UserRole role, EmployeeDepartment? audience) =>
        IsOwner(role) || IsCountryManager(role) ||
        (role == UserRole.HeadOfMarketing && audience is EmployeeDepartment.Marketing or EmployeeDepartment.Interns) ||
        ((IsDepartmentHead(role) || role == UserRole.Receptionist) && audience == DepartmentScope(role));
    public static bool CanDeleteAnnouncement(User actor, Announcement notice) =>
        IsOwner(actor.Role) || (CanCreateNotices(actor.Role) && actor.Id == notice.AuthorId &&
            CanTargetAudience(actor.Role, notice.Department));
    public static bool IsPrimaryAdmin(User user) => user.Role == UserRole.Admin && user.Username.Equals("admin", StringComparison.OrdinalIgnoreCase);
    // Distinct from authorization privileges: managers retain management permissions,
    // but everybody except the original seeded admin records attendance.
    public static bool RequiresAttendance(User user) => !IsPrimaryAdmin(user);
    public static bool CanManageRole(UserRole actor, UserRole target) =>
        target != UserRole.SuperAdmin && IsOwner(actor);
}
