import Foundation

// MARK: - SVGExporter (ADR-066 Phase 4)

/// **ADR-066 Phase 4** — chart 데이터를 SVG (vector) 형식으로 export.
///
/// PNG (raster)와 달리 SVG는 vector — scale 무한대로 확대해도 깨지지 않음.
/// 사용 예: 보고서 / 논문 / web 게시.
public enum SVGExporter {
    /// SVG document header.
    public static let header = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
    """

    /// **Line chart SVG** — values 배열을 X = index, Y = value로 그림.
    /// 자동 scale (data min/max를 viewBox에 맞춤).
    public static func lineChart(
        values: [Double],
        title: String = "",
        width: Int = 800,
        height: Int = 300,
        strokeColor: String = "#3b82f6",  // blue
        fillColor: String = "#3b82f680",  // blue with alpha
        showArea: Bool = true
    ) -> String {
        guard !values.isEmpty else {
            return emptyChart(width: width, height: height, message: "no data")
        }
        let padding = 40
        let chartW = width - 2 * padding
        let chartH = height - 2 * padding

        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.0001)

        func xCoord(_ i: Int) -> Double {
            guard values.count > 1 else { return Double(padding) }
            return Double(padding) + Double(i) * Double(chartW) / Double(values.count - 1)
        }
        func yCoord(_ v: Double) -> Double {
            let normalized = (v - minV) / range
            return Double(height - padding) - normalized * Double(chartH)
        }

        // line path
        var pathD = ""
        for (i, v) in values.enumerated() {
            let cmd = i == 0 ? "M" : "L"
            pathD += "\(cmd) \(xCoord(i)),\(yCoord(v)) "
        }

        // area path (line + close to bottom)
        var areaD = pathD
        areaD += "L \(xCoord(values.count - 1)),\(height - padding) "
        areaD += "L \(xCoord(0)),\(height - padding) Z"

        var svg = "\(header) width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\n"
        svg += "  <rect width=\"\(width)\" height=\"\(height)\" fill=\"#fafafa\"/>\n"
        if !title.isEmpty {
            svg += "  <text x=\"\(width / 2)\" y=\"20\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\" font-weight=\"bold\">\(escape(title))</text>\n"
        }
        // Y axis labels
        svg += "  <text x=\"\(padding - 5)\" y=\"\(padding + 4)\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"10\" fill=\"#666\">\(format(maxV))</text>\n"
        svg += "  <text x=\"\(padding - 5)\" y=\"\(height - padding + 4)\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"10\" fill=\"#666\">\(format(minV))</text>\n"
        // X/Y grid lines
        svg += "  <line x1=\"\(padding)\" y1=\"\(padding)\" x2=\"\(padding)\" y2=\"\(height - padding)\" stroke=\"#ccc\" stroke-width=\"1\"/>\n"
        svg += "  <line x1=\"\(padding)\" y1=\"\(height - padding)\" x2=\"\(width - padding)\" y2=\"\(height - padding)\" stroke=\"#ccc\" stroke-width=\"1\"/>\n"
        // area
        if showArea {
            svg += "  <path d=\"\(areaD)\" fill=\"\(fillColor)\" stroke=\"none\"/>\n"
        }
        // line
        svg += "  <path d=\"\(pathD)\" fill=\"none\" stroke=\"\(strokeColor)\" stroke-width=\"2\"/>\n"
        // points
        for (i, v) in values.enumerated() {
            svg += "  <circle cx=\"\(xCoord(i))\" cy=\"\(yCoord(v))\" r=\"3\" fill=\"\(strokeColor)\"/>\n"
        }
        svg += "</svg>"
        return svg
    }

    /// **Bar chart SVG**.
    public static func barChart(
        labels: [String],
        values: [Double],
        title: String = "",
        width: Int = 800,
        height: Int = 300,
        barColor: String = "#3b82f6"
    ) -> String {
        guard values.count == labels.count, !values.isEmpty else {
            return emptyChart(width: width, height: height, message: "no data")
        }
        let padding = 40
        let chartW = width - 2 * padding
        let chartH = height - 2 * padding

        let maxV = values.max() ?? 1
        let barWidth = Double(chartW) / Double(values.count) - 4

        var svg = "\(header) width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\n"
        svg += "  <rect width=\"\(width)\" height=\"\(height)\" fill=\"#fafafa\"/>\n"
        if !title.isEmpty {
            svg += "  <text x=\"\(width / 2)\" y=\"20\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\" font-weight=\"bold\">\(escape(title))</text>\n"
        }

        for (i, v) in values.enumerated() {
            let normalized = v / max(maxV, 0.0001)
            let h = normalized * Double(chartH)
            let x = Double(padding) + Double(i) * (barWidth + 4)
            let y = Double(height - padding) - h
            svg += "  <rect x=\"\(x)\" y=\"\(y)\" width=\"\(barWidth)\" height=\"\(h)\" fill=\"\(barColor)\"/>\n"
            // value label
            svg += "  <text x=\"\(x + barWidth / 2)\" y=\"\(y - 4)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"10\" fill=\"#333\">\(format(v))</text>\n"
            // label
            svg += "  <text x=\"\(x + barWidth / 2)\" y=\"\(height - padding + 14)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"10\" fill=\"#666\">\(escape(labels[i]))</text>\n"
        }
        svg += "</svg>"
        return svg
    }

    private static func emptyChart(width: Int, height: Int, message: String) -> String {
        """
        \(header) width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
          <rect width="\(width)" height="\(height)" fill="#fafafa"/>
          <text x="\(width / 2)" y="\(height / 2)" text-anchor="middle" font-family="sans-serif" font-size="14" fill="#999">\(escape(message))</text>
        </svg>
        """
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func format(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.4f", value)
    }
}
