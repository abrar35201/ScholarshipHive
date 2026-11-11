-- ScholarshipHive PostgreSQL checks for pgAdmin 4 Query Tool
-- Names are case-sensitive because EF uses quoted table identifiers.
SELECT current_database() AS database_name, current_user AS connected_role;
SELECT "MigrationId" FROM "__EFMigrationsHistory" ORDER BY "MigrationId";
SELECT 'Users' AS table_name, COUNT(*) AS row_count FROM "Users"
UNION ALL SELECT 'Attendances', COUNT(*) FROM "Attendances"
UNION ALL SELECT 'AllowedRouters', COUNT(*) FROM "AllowedRouters"
UNION ALL SELECT 'AllowedLocations', COUNT(*) FROM "AllowedLocations"
UNION ALL SELECT 'LoginHistories', COUNT(*) FROM "LoginHistories"
UNION ALL SELECT 'Reports', COUNT(*) FROM "Reports"
UNION ALL SELECT 'ReportFiles', COUNT(*) FROM "ReportFiles"
UNION ALL SELECT 'AuditReports', COUNT(*) FROM "AuditReports"
UNION ALL SELECT 'VisitorRecords', COUNT(*) FROM "VisitorRecords"
UNION ALL SELECT 'ReceptionConsents', COUNT(*) FROM "ReceptionConsents"
UNION ALL SELECT 'LeaveRequests', COUNT(*) FROM "LeaveRequests"
UNION ALL SELECT 'ShiftChangeRequests', COUNT(*) FROM "ShiftChangeRequests"
UNION ALL SELECT 'Announcements', COUNT(*) FROM "Announcements"
UNION ALL SELECT 'UserNotices', COUNT(*) FROM "UserNotices"
UNION ALL SELECT 'AuditEvents', COUNT(*) FROM "AuditEvents"
UNION ALL SELECT 'DataProtectionKeys', COUNT(*) FROM "DataProtectionKeys";
SELECT "Id", "Username", "Role", "Department", "IsActive", "IsApproved" FROM "Users" ORDER BY "Id";
SELECT "UserId", "Date", "CheckInTime", "CheckOutTime", "LastPingAt" FROM "Attendances" ORDER BY "Date" DESC LIMIT 20;
SELECT "Name", "Bssid", "IsActive" FROM "AllowedRouters";
SELECT "Name", "Latitude", "Longitude", "RadiusMeters", "IsActive" FROM "AllowedLocations";
SELECT "AtUtc", "Actor", "Action", "EntityType" FROM "AuditEvents" ORDER BY "AtUtc" DESC LIMIT 20;
