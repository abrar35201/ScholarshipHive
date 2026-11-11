using System.Text.Json;
using System.Text.Json.Serialization;

namespace ScholarshipHive.Server.Services;

/// Npgsql returns `timestamp` columns as DateTime with Kind=Unspecified even
/// though every value the app writes is DateTime.UtcNow — so without this,
/// System.Text.Json serializes them with no "Z"/offset, and clients (the
/// Flutter app's DateTime.parse) silently treat the bare string as already
/// being in their own local time instead of UTC. That made every timestamp
/// shown in the mobile app look exactly PakistanOffset hours behind, since
/// ".toLocal()" became a no-op on a value Dart already believed was local.
/// This forces Kind=Utc on the way out so the "Z" is always present.
public class UtcDateTimeConverter : JsonConverter<DateTime>
{
    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => reader.GetDateTime();

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options)
    {
        var utc = value.Kind == DateTimeKind.Utc ? value : DateTime.SpecifyKind(value, DateTimeKind.Utc);
        writer.WriteStringValue(utc);
    }
}
