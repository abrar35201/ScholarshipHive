using System.Globalization;
using System.Text;

namespace ScholarshipHive.Server.Services;

public record ChartPoint(string Label, double Value);
public record DonutSegment(double Value, string Color);

/// Tiny, dependency-free inline-SVG chart renderer — no chart.js/JS runtime needed,
/// so these render identically server-side, in an email export, or with JS disabled.
/// Mirrors the shape of a typical charting library's bar/area/donut primitives, just
/// emitting raw SVG markup strings instead of mounting a canvas.
public static class ChartSvg
{
    private static string F(double n) => n.ToString("0.##", CultureInfo.InvariantCulture);

    public static string Bars(IReadOnlyList<ChartPoint> data, int w, int h, string barColor = "#0891B2", string emptyColor = "#DDEDF0")
    {
        var max = data.Count == 0 ? 1 : Math.Max(data.Max(x => x.Value), 1);
        var bw = (double)w / Math.Max(data.Count, 1);
        var sb = new StringBuilder();
        sb.Append($"<svg viewBox=\"0 0 {w} {h}\" style=\"width:100%;height:{h}px;display:block\">");
        for (var i = 0; i < data.Count; i++)
        {
            var x = data[i];
            var bh = Math.Max(x.Value / max * (h - 22), 2);
            var bx = i * bw + bw * 0.22;
            var bwid = bw * 0.56;
            var color = x.Value > 0 ? barColor : emptyColor;
            sb.Append($"<rect x=\"{F(bx)}\" y=\"{F(h - 22 - bh)}\" width=\"{F(bwid)}\" height=\"{F(bh)}\" rx=\"4\" fill=\"{color}\"/>");
            sb.Append($"<text x=\"{F(bx + bwid / 2)}\" y=\"{h - 6}\" text-anchor=\"middle\" font-family=\"Outfit,sans-serif\" font-size=\"10.5\" fill=\"#5F8189\">{System.Net.WebUtility.HtmlEncode(x.Label)}</text>");
        }
        sb.Append("</svg>");
        return sb.ToString();
    }

    /// [fixedWidth] renders the SVG at exactly `w` CSS pixels instead of stretching
    /// to 100% of its container — pair with a scrollable (overflow-x:auto) wrapper
    /// so a wide `w` (many data points, e.g. an hourly 24-point day) actually scrolls
    /// instead of just cramming every point/label into whatever width the container
    /// happens to have.
    public static string Area(IReadOnlyList<ChartPoint> data, int w, int h, string lineColor = "#0891B2", bool fixedWidth = false)
    {
        if (data.Count == 0) return "<svg></svg>";
        var max = Math.Max(data.Max(x => x.Value), 1);
        var step = (w - 30.0) / Math.Max(data.Count - 1, 1);
        var pts = data.Select((x, i) => (X: 15 + i * step, Y: h - 24 - (x.Value / max) * (h - 42))).ToList();
        var line = string.Join(" ", pts.Select((p, i) => $"{(i == 0 ? "M" : "L")}{F(p.X)} {F(p.Y)}"));
        var sb = new StringBuilder();
        var gradId = "ag" + Guid.NewGuid().ToString("N")[..6];
        var widthStyle = fixedWidth ? $"{w}px" : "100%";
        sb.Append($"<svg viewBox=\"0 0 {w} {h}\" style=\"width:{widthStyle};height:{h}px;display:block\">");
        sb.Append($"<defs><linearGradient id=\"{gradId}\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0%\" stop-color=\"{lineColor}\" stop-opacity=\".26\"/><stop offset=\"100%\" stop-color=\"{lineColor}\" stop-opacity=\"0\"/></linearGradient></defs>");
        sb.Append($"<path d=\"{line} L{F(pts[^1].X)} {h - 24} L{F(pts[0].X)} {h - 24} Z\" fill=\"url(#{gradId})\"/>");
        sb.Append($"<path d=\"{line}\" fill=\"none\" stroke=\"{lineColor}\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>");
        foreach (var p in pts)
            sb.Append($"<circle cx=\"{F(p.X)}\" cy=\"{F(p.Y)}\" r=\"3.2\" fill=\"#fff\" stroke=\"{lineColor}\" stroke-width=\"2\"/>");
        for (var i = 0; i < data.Count; i++)
        {
            if (data.Count > 16 && i % 3 != 0 && i != data.Count - 1) continue;
            sb.Append($"<text x=\"{F(pts[i].X)}\" y=\"{h - 7}\" text-anchor=\"middle\" font-family=\"Outfit,sans-serif\" font-size=\"10\" fill=\"#5F8189\">{System.Net.WebUtility.HtmlEncode(data[i].Label)}</text>");
        }
        sb.Append("</svg>");
        return sb.ToString();
    }

    /// centerLabel/centerSub render in the donut's hole (e.g. "78%" / "present").
    public static string Donut(IReadOnlyList<DonutSegment> segments, int size, string centerLabel, string centerSub)
    {
        var r = size / 2.0 - 14;
        var cx = size / 2.0;
        var cy = size / 2.0;
        var c = 2 * Math.PI * r;
        var total = Math.Max(segments.Sum(s => s.Value), 0.0001);
        double acc = 0;
        var sb = new StringBuilder();
        sb.Append($"<svg viewBox=\"0 0 {size} {size}\" style=\"width:{size}px;height:{size}px;display:block\">");
        sb.Append($"<circle cx=\"{F(cx)}\" cy=\"{F(cy)}\" r=\"{F(r)}\" fill=\"none\" stroke=\"#EDF6F8\" stroke-width=\"18\"/>");
        foreach (var s in segments)
        {
            var frac = s.Value / total * 100;
            var len = c * frac / 100;
            var dash = $"{F(len)} {F(c - len)}";
            var off = F(-c * acc / 100);
            acc += frac;
            sb.Append($"<circle cx=\"{F(cx)}\" cy=\"{F(cy)}\" r=\"{F(r)}\" fill=\"none\" stroke=\"{s.Color}\" stroke-width=\"18\" stroke-dasharray=\"{dash}\" stroke-dashoffset=\"{off}\" transform=\"rotate(-90 {F(cx)} {F(cy)})\" stroke-linecap=\"butt\"/>");
        }
        sb.Append($"<text x=\"{F(cx)}\" y=\"{F(cy - 4)}\" text-anchor=\"middle\" font-family=\"Sora,sans-serif\" font-size=\"26\" font-weight=\"600\" fill=\"#062026\">{System.Net.WebUtility.HtmlEncode(centerLabel)}</text>");
        sb.Append($"<text x=\"{F(cx)}\" y=\"{F(cy + 15)}\" text-anchor=\"middle\" font-family=\"Outfit,sans-serif\" font-size=\"11\" fill=\"#5F8189\">{System.Net.WebUtility.HtmlEncode(centerSub)}</text>");
        sb.Append("</svg>");
        return sb.ToString();
    }
}
