namespace ScholarshipHive.Server.Services;
public record CallingFormTemplate(string Id, string Name, string Country, string FileName);
public static class CallingFormCatalog
{
    // These are exact, unmodified source PDF documents from the company's shared Drive folder.
    // Do not make them public via wwwroot: the controller verifies calling-team membership.
    public static readonly IReadOnlyList<CallingFormTemplate> All = new[] {
        new CallingFormTemplate("china", "China — Admission Consent", "China", "china.pdf"),
        new CallingFormTemplate("france", "France — Consent Form", "France", "france.pdf"),
        new CallingFormTemplate("germany-nonrefund", "Germany — Non-refundable", "Germany", "germany-nonrefund.pdf"),
        new CallingFormTemplate("germany-90", "Germany — 90% Refund", "Germany", "germany-90.pdf"),
        new CallingFormTemplate("germany-80", "Germany — 80% Refund", "Germany", "germany-80.pdf"),
        new CallingFormTemplate("germany-70", "Germany — 70% Refund", "Germany", "germany-70.pdf"),
        new CallingFormTemplate("hungary", "Hungary — Consent Form", "Hungary", "hungary.pdf"),
        new CallingFormTemplate("sweden-50-spouse", "Sweden — 50% Refund With Spouse", "Sweden", "sweden-50-spouse.pdf"),
        new CallingFormTemplate("italy-bs-nonrefund", "Italy BS — Non-refundable", "Italy", "italy-bs-nonrefund.pdf"),
        new CallingFormTemplate("italy-bs-50", "Italy BS — 50% Refund", "Italy", "italy-bs-50.pdf"),
        new CallingFormTemplate("italy-bs-30", "Italy BS — 30% Refund", "Italy", "italy-bs-30.pdf"),
        new CallingFormTemplate("italy-ms-nonrefund", "Italy MS — Non-refundable", "Italy", "italy-ms-nonrefund.pdf"),
        new CallingFormTemplate("italy-ms-50", "Italy MS — 50% Refund", "Italy", "italy-ms-50.pdf"),
        new CallingFormTemplate("italy-ms-30", "Italy MS — 30% Refund", "Italy", "italy-ms-30.pdf")
    };
    public static CallingFormTemplate? Find(string? id) => All.FirstOrDefault(x => x.Id == id);

    // Cross-country applicant fields shared across PDF variants. The original PDF
    // remains the legal source of terms; this saves data-entry DRAFTS only.
    public static readonly IReadOnlyList<string> Fields = new [] {
      "surname", "givenName", "dateOfBirth", "gender", "nationality", "maritalStatus",
      "domicileCity", "placeOfBirth", "cnic", "cnicIssueDate", "cnicExpiryDate",
      "passportNumber", "passportIssueDate", "passportExpiryDate", "whatsapp",
      "address", "city", "province", "postalCode", "emergencyContactName",
      "emergencyContactPhone", "guardianRelationship", "qualification", "degreeTitle",
      "university", "degreeStartDate", "degreeEndDate", "educationCountry",
      "rollNumber", "cgpaOrPercentage", "college", "board", "marksObtained", "totalMarks",
      "program", "intake", "consultancyFee", "advancePaid", "notes",
      "matricMarks", "intermediateMarks", "universityOffer", "englishTestResult",
      "visaStatus", "spouseName", "spousePassportNumber", "spouseContact",
      "universityApplicationFee", "clientInitials", "counselorName"
    };
    public static bool ValidField(string name) => Fields.Contains(name, StringComparer.Ordinal);
}
