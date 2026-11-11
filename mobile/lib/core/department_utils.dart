/// Matches the backend's EmployeeDepartment enum ordinals (Calling=0,
/// Processing=1, Others=2, Interns=3) — no JsonStringEnumConverter is
/// registered server-side, so department is sent over the wire as this int,
/// not a string.
int departmentToInt(String department) => switch (department) {
      'Processing' => 1,
      'Others' => 2,
      'Interns' => 3,
      'Marketing' => 4,
      _ => 0,
    };

/// Matches the backend's ShiftType enum ordinals (Day=0, Night=1,
/// Internship=2) — sent over the wire as this int, same reasoning as
/// [departmentToInt].
int shiftTypeToInt(String shiftType) => switch (shiftType) {
      'Night' => 1,
      'Internship' => 2,
      _ => 0,
    };
