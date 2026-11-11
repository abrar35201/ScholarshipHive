# ScholarshipHive AI Assistant — Google Gemini (free tier)

This source package contains **no API key**. Google creates a key for **your** Google account/project; we cannot generate a working key for you.

1. Visit https://aistudio.google.com/apikey, sign in, and click **Create API key**.
2. In the PowerShell terminal where you will start .NET, type:

```powershell
$env:Gemini__ApiKey = "PASTE_YOUR_AI_STUDIO_KEY_HERE"
cd "backend\ScholarshipHive.Server"
dotnet run
```

3. Web Admin → **AI Assistant**; ask a simple question like "How many employees are active?".

The default model is `gemini-3.5-flash-lite`, currently listed by Google with a free tier. Availability, rate limits and conditions depend on Google's account/project policies. If your key cannot access that model, consult your Google AI Studio model list and choose an eligible model:

```powershell
$env:Gemini__Model = "gemini-3.5-flash-lite"
```

For Railway: configure `Gemini__ApiKey` as a server **environment variable** (not in a committed file or Flutter code). Keep the key server-side. Never share your key in ZIPs/screenshots. Google may use free-tier submissions to improve products; do not send confidential employee records without informed company consent and checking Google's data-use terms.

If AI Assistant reports 401/403, verify your key. 404 means the selected model is unavailable. 429 means quota/rate limit. No network access was available in this build environment to validate a live Gemini request.
