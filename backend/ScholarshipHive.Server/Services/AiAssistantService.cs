using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Services;

/// Lets an Admin/Auditor ask questions in plain language ("kitni martaba ghulam late aya
/// iss hafte?") and get answers grounded in real data, instead of manually digging through
/// tables. Built on Google Gemini's function-calling: the model is given a small set of
/// read-only query tools and decides which ones to call — it never invents numbers, and it
/// can chain several lookups together to answer a broader question on its own.
///
/// Uses Gemini rather than Anthropic/OpenAI specifically because Google AI Studio's free
/// tier issues an API key with no billing/card required, unlike the others — a hard
/// requirement for this project.
public class AiAssistantService
{
    // "-latest" alias rather than a dated version — Google retires dated model IDs for
    // new API keys fairly often (confirmed directly: gemini-2.0-flash and
    // gemini-2.5-flash-lite were both already unavailable to this key), so pinning to a
    // specific version risks the assistant silently 404ing again after some future cutoff.
    // Current free-tier eligible model (subject to Google's per-project limits).
    // Set Gemini__Model if a project's available models change.
    private const string DefaultModel = "gemini-3.5-flash-lite";
    private const int MaxToolRounds = 6;

    private readonly AppDbContext _db;
    private readonly IConfiguration _config;
    private readonly IHttpClientFactory _httpClientFactory;

    public AiAssistantService(AppDbContext db, IConfiguration config, IHttpClientFactory httpClientFactory)
    {
        _db = db;
        _config = config;
        _httpClientFactory = httpClientFactory;
    }

    // Railway's Gemini__ApiKey environment variable binds to this setting.
    // Keep credential lookup in configuration and never add it to the URL/logs.
    private string? ApiKey => _config["Gemini:ApiKey"];
    public bool IsConfigured => !string.IsNullOrWhiteSpace(ApiKey);

    public async Task<string> AskAsync(string question, int? scopedUserId, List<ChatTurnDto> history)
    {
        var apiKey = ApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return "Gemini is not configured. Set Gemini:ApiKey (Railway: Gemini__ApiKey) in backend configuration.";
        }

        string? scopedUsername = null;
        if (scopedUserId.HasValue)
        {
            scopedUsername = await _db.Users.Where(u => u.Id == scopedUserId.Value).Select(u => u.Username).FirstOrDefaultAsync();
        }

        var client = _httpClientFactory.CreateClient("Gemini");
        var model = _config["Gemini:Model"] ?? DefaultModel;
        if (!System.Text.RegularExpressions.Regex.IsMatch(model, @"^[a-zA-Z0-9._-]{1,80}$"))
            return "Gemini model configuration is invalid.";
        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent";

        var contents = new JsonArray();
        foreach (var turn in history)
        {
            contents.Add(new JsonObject
            {
                ["role"] = turn.Role == "assistant" ? "model" : "user",
                ["parts"] = new JsonArray(new JsonObject { ["text"] = turn.Content })
            });
        }
        contents.Add(new JsonObject
        {
            ["role"] = "user",
            ["parts"] = new JsonArray(new JsonObject { ["text"] = question })
        });

        for (var round = 0; round < MaxToolRounds; round++)
        {
            var requestBody = new JsonObject
            {
                ["system_instruction"] = new JsonObject
                {
                    ["parts"] = new JsonArray(new JsonObject { ["text"] = BuildSystemPrompt(scopedUsername) })
                },
                ["contents"] = JsonNode.Parse(contents.ToJsonString()),
                ["tools"] = new JsonArray(new JsonObject { ["function_declarations"] = BuildToolDefinitions() })
            };

            HttpResponseMessage response;
            string responseText;
            try
            {
                using var message = new HttpRequestMessage(HttpMethod.Post, url);
                // Never put the API key in a URL, mobile app, logs, or a committed file.
                message.Headers.TryAddWithoutValidation("x-goog-api-key", apiKey);
                message.Content = new StringContent(requestBody.ToJsonString(), Encoding.UTF8, "application/json");
                response = await client.SendAsync(message);
                using (response)
                {
                    responseText = await response.Content.ReadAsStringAsync();
                }
            }
            catch (OperationCanceledException)
            {
                return "Gemini took too long to respond. Please try again shortly.";
            }
            catch (HttpRequestException)
            {
                return "The AI Assistant couldn't reach Gemini right now. Check backend network access and try again shortly.";
            }

            if (!response.IsSuccessStatusCode)
            {
                return response.StatusCode switch
                {
                    System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden => "Gemini API key rejected. Create/verify your Google AI Studio key in backend configuration.",
                    System.Net.HttpStatusCode.TooManyRequests => "Gemini's free-tier request quota has been reached. Please retry later.",
                    System.Net.HttpStatusCode.NotFound => "Selected Gemini model isn't available for this API key. Set Gemini__Model to an available free-tier model.",
                    System.Net.HttpStatusCode.BadRequest => "Gemini rejected the request. Check the configured model and request compatibility.",
                    _ => $"Gemini returned HTTP {(int)response.StatusCode}. Please retry or check the model configuration."
                };
            }

            JsonObject root;
            try { root = JsonNode.Parse(responseText)?.AsObject() ?? throw new JsonException(); }
            catch (Exception ex) when (ex is JsonException or InvalidOperationException) { return "Gemini returned an unreadable response. Please try again."; }
            var candidates = root["candidates"]?.AsArray();
            var firstCandidate = candidates?.FirstOrDefault();
            var partsNode = firstCandidate?["content"]?["parts"]?.AsArray();
            if (partsNode is null)
            {
                return "The AI Assistant didn't return a usable answer — try rephrasing your question.";
            }

            var functionCalls = partsNode.Where(p => p!["functionCall"] is not null).ToList();

            // Echo the model's own turn back into the conversation before continuing.
            contents.Add(new JsonObject
            {
                ["role"] = "model",
                ["parts"] = JsonNode.Parse(partsNode.ToJsonString())
            });

            if (functionCalls.Count > 0)
            {
                var responseParts = new JsonArray();
                foreach (var call in functionCalls)
                {
                    var functionCall = call!["functionCall"]!.AsObject();
                    var name = functionCall["name"]!.GetValue<string>();
                    var args = functionCall.TryGetPropertyValue("args", out var a) && a is not null ? a.AsObject() : new JsonObject();
                    var result = await ExecuteToolAsync(name, args);

                    responseParts.Add(new JsonObject
                    {
                        ["functionResponse"] = new JsonObject
                        {
                            ["name"] = name,
                            ["response"] = new JsonObject { ["result"] = result }
                        }
                    });
                }
                contents.Add(new JsonObject { ["role"] = "user", ["parts"] = responseParts });
                continue;
            }

            var textPart = partsNode.FirstOrDefault(p => p!["text"] is not null);
            return textPart?["text"]?.GetValue<string>() ?? "I couldn't come up with an answer for that.";
        }

        return "That question needed more lookups than I could fit in one go — try asking something a bit more specific.";
    }

    private static string BuildSystemPrompt(string? scopedUsername)
    {
        var scope = scopedUsername is null
            ? "The admin has not selected a specific person, so answer across the whole company if the question calls for it (use list_users / get_dashboard_stats to see who exists)."
            : $"The admin is currently viewing the profile of the user \"{scopedUsername}\" — assume questions are about this person unless they clearly ask about someone else or the whole company.";

        return "You are the ScholarshipHive AI Assistant, helping a company Admin or Auditor understand employee " +
               "attendance, daily performance reports, check-in/check-out history, and audit reports Auditors have " +
               "compiled. Calling department reports have numeric KPI fields; Processing, Others, and Interns " +
               "department reports are free-text write-ups (with optional attached files) instead. " +
               "Always use the tools to look up real data before answering — never guess or make up numbers. " +
               "Reply concisely, in whichever language the admin wrote in (English or Roman Urdu). " + scope;
    }

    private static JsonArray BuildToolDefinitions() => new()
    {
        Tool("list_users", "List every user with their role, department, and active/approval status.",
            new JsonObject()),
        Tool("get_dashboard_stats", "Get company-wide numbers: total users, how many are checked in right now, how many reports were submitted today, active routers, pending approvals.",
            new JsonObject()),
        Tool("get_user_attendance", "Get a user's daily attendance (check-in/check-out time, whether they submitted a report) for their last N days.",
            new JsonObject
            {
                ["type"] = "object",
                ["properties"] = new JsonObject
                {
                    ["username"] = new JsonObject { ["type"] = "string", ["description"] = "The user's username" },
                    ["days"] = new JsonObject { ["type"] = "integer", ["description"] = "How many days back to look (default 30)" }
                },
                ["required"] = new JsonArray("username")
            }),
        Tool("get_user_reports", "Get a user's daily KPI reports (Unread Chats, New Leads, Qualified Leads, Follow Up, Calls, Potential, Walk-ins, Conversion) for their last N days.",
            new JsonObject
            {
                ["type"] = "object",
                ["properties"] = new JsonObject
                {
                    ["username"] = new JsonObject { ["type"] = "string" },
                    ["days"] = new JsonObject { ["type"] = "integer", ["description"] = "Default 30" }
                },
                ["required"] = new JsonArray("username")
            }),
        Tool("get_user_checkin_history", "Get a user's full check-in/check-out event timeline (every individual event with its exact time and which router), not just the daily summary — use this for 'how many times did X check in/out' type questions.",
            new JsonObject
            {
                ["type"] = "object",
                ["properties"] = new JsonObject
                {
                    ["username"] = new JsonObject { ["type"] = "string" },
                    ["days"] = new JsonObject { ["type"] = "integer", ["description"] = "Default 7" }
                },
                ["required"] = new JsonArray("username")
            }),
        Tool("get_audit_reports", "Get the audit reports Auditors have compiled and uploaded — their write-up of findings across everyone's work, plus how many files each has attached. Use this when asked about audits, audit findings, or what an Auditor has reviewed/uploaded.",
            new JsonObject
            {
                ["type"] = "object",
                ["properties"] = new JsonObject
                {
                    ["limit"] = new JsonObject { ["type"] = "integer", ["description"] = "Most recent N reports to return, default 20" }
                }
            }),
    };

    private static JsonObject Tool(string name, string description, JsonObject parameters)
    {
        if (parameters.Count == 0)
        {
            parameters["type"] = "object";
            parameters["properties"] = new JsonObject();
        }
        return new JsonObject { ["name"] = name, ["description"] = description, ["parameters"] = parameters };
    }

    private async Task<string> ExecuteToolAsync(string toolName, JsonObject input)
    {
        try
        {
            switch (toolName)
            {
                case "list_users":
                {
                    var users = await _db.Users
                        .Select(u => new { u.Username, u.FullName, Role = u.Role.ToString(), Department = u.Department.ToString(), u.IsActive, u.IsApproved })
                        .ToListAsync();
                    return JsonSerializer.Serialize(users);
                }

                case "get_dashboard_stats":
                {
                    var today = DateTimeExtensions.PakistanToday();
                    var stats = new
                    {
                        TotalUsers = await _db.Users.CountAsync(),
                        CheckedInNow = await _db.Attendances.CountAsync(a => a.Date == today && a.CheckOutTime == null),
                        ReportsToday = await _db.Attendances.CountAsync(a => a.Date == today && a.ReportSubmitted),
                        ConfiguredRouters = await _db.AllowedRouters.CountAsync(r => r.IsActive),
                        PendingApprovals = await _db.Users.CountAsync(u => !u.IsApproved)
                    };
                    return JsonSerializer.Serialize(stats);
                }

                case "get_user_attendance":
                {
                    var username = input["username"]!.GetValue<string>();
                    var days = input.TryGetPropertyValue("days", out var d) && d is not null ? d.GetValue<int>() : 30;
                    var user = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == username.ToLower());
                    if (user is null) return $"No user found with username '{username}'.";

                    var since = DateTimeExtensions.PakistanToday().AddDays(-days);
                    var attendance = await _db.Attendances
                        .Where(a => a.UserId == user.Id && a.Date >= since)
                        .OrderByDescending(a => a.Date)
                        .ToListAsync();

                    var shaped = attendance.Select(a => new
                    {
                        Date = a.Date.ToString(),
                        CheckIn = a.CheckInTime.ToPakistanTime().ToString("hh:mm:ss tt"),
                        CheckOut = a.CheckOutTime.HasValue ? a.CheckOutTime.Value.ToPakistanTime().ToString("hh:mm:ss tt") : "still checked in",
                        a.ReportSubmitted
                    });
                    return JsonSerializer.Serialize(shaped);
                }

                case "get_user_reports":
                {
                    var username = input["username"]!.GetValue<string>();
                    var days = input.TryGetPropertyValue("days", out var d) && d is not null ? d.GetValue<int>() : 30;
                    var user = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == username.ToLower());
                    if (user is null) return $"No user found with username '{username}'.";

                    var since = DateTimeExtensions.PakistanToday().AddDays(-days);
                    var reports = await _db.Reports
                        .Include(r => r.Attendance)
                        .Include(r => r.Files)
                        .Where(r => r.UserId == user.Id && r.Attendance!.Date >= since)
                        .OrderByDescending(r => r.Attendance!.Date)
                        .ToListAsync();

                    // Calling reports use the numeric KPI fields; every other department
                    // (Processing/Others/Interns) uses free-text + attached files instead,
                    // so the numeric fields are meaningless zeros for them and shouldn't
                    // be shown as real data.
                    object shaped = user.Department == EmployeeDepartment.Calling
                        ? reports.Select(r => new
                        {
                            Date = r.Attendance!.Date.ToString(),
                            r.UnreadChats,
                            r.NewLeads,
                            r.QualifiedLeads,
                            r.FollowUp,
                            r.Calls,
                            r.Potential,
                            r.WalkIns,
                            r.Conversion
                        })
                        : reports.Select(r => new
                        {
                            Date = r.Attendance!.Date.ToString(),
                            ReportText = r.TextContent,
                            AttachedFileCount = r.Files.Count
                        });
                    return JsonSerializer.Serialize(shaped);
                }

                case "get_user_checkin_history":
                {
                    var username = input["username"]!.GetValue<string>();
                    var days = input.TryGetPropertyValue("days", out var d) && d is not null ? d.GetValue<int>() : 7;
                    var user = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == username.ToLower());
                    if (user is null) return $"No user found with username '{username}'.";

                    var sinceUtc = DateTime.UtcNow.AddDays(-days);
                    var history = await _db.LoginHistories
                        .Where(h => h.UserId == user.Id && h.Timestamp >= sinceUtc)
                        .OrderByDescending(h => h.Timestamp)
                        .ToListAsync();

                    var routerNames = await new NetworkAccessService(_db).GetRouterNameLookupAsync();
                    var shaped = history.Select(h => new
                    {
                        Event = h.EventType.ToString(),
                        Time = h.Timestamp.ToPakistanTime().ToString("yyyy-MM-dd hh:mm:ss tt"),
                        Router = h.Bssid is not null && routerNames.TryGetValue(NetworkAccessService.Normalize(h.Bssid), out var name) ? name : h.Bssid
                    });
                    return JsonSerializer.Serialize(shaped);
                }

                case "get_audit_reports":
                {
                    var limit = input.TryGetPropertyValue("limit", out var l) && l is not null ? l.GetValue<int>() : 20;
                    var audits = await _db.AuditReports
                        .Include(a => a.AuditorUser)
                        .Include(a => a.Files)
                        .OrderByDescending(a => a.CreatedAt)
                        .Take(limit)
                        .ToListAsync();

                    var shaped = audits.Select(a => new
                    {
                        a.Title,
                        Auditor = a.AuditorUser?.Username,
                        CreatedAt = a.CreatedAt.ToPakistanTime().ToString("yyyy-MM-dd hh:mm:ss tt"),
                        Findings = a.TextContent,
                        AttachedFileCount = a.Files.Count
                    });
                    return JsonSerializer.Serialize(shaped);
                }

                default:
                    return $"Unknown tool: {toolName}";
            }
        }
        catch (Exception)
        {
            return "That data lookup failed. Please retry, or ask an administrator to check the service.";
        }
    }
}
