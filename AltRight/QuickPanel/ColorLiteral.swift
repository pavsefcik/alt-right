import AppKit
import Foundation

/// A colour that an entire copied string spells out — `#FE92F5`, `254, 146,
/// 245`, `rgb(254 146 245 / 50%)`, `hsl(303 43% 96%)`, `hsv(303, 43%, 96%)`,
/// `tomato`.
///
/// Detection is deliberately whole-string: a sentence that merely mentions a
/// colour stays a plain text row. The copy history keeps its one promise — the
/// row shows exactly the string that lands on the pasteboard — and this type
/// only decides how that string is *drawn*.
struct ColorLiteral: Equatable {
    let red: Double    // 0…1
    let green: Double
    let blue: Double
    let alpha: Double  // 0…1

    /// The string this was parsed from, trimmed, verbatim.
    let source: String

    /// Which family of notation matched, for the tooltip.
    enum Origin: String, Equatable {
        case hex
        case rgb = "rgb()"
        case hsl = "hsl()"
        case hsv = "hsv()"
        case named = "CSS name"
        case ncs = "NCS"
        case ral = "RAL Classic"
    }

    let origin: Origin

    /// The name the standard gives the colour, when it has one —
    /// `RAL 3000 Flame red`, `NCS S 1050-Y90R`. `nil` for RGB notations.
    var label: String?
}

// MARK: - Parsing

extension ColorLiteral {
    /// `nil` unless the *whole* trimmed string is one colour.
    static func parse(_ raw: String) -> ColorLiteral? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              text.count <= 64,
              !text.contains(where: { $0.isNewline }) else {
            return nil
        }

        return hex(text)
            ?? function(text)
            ?? triplet(text)
            ?? named(text)
            ?? standard(text)
    }

    /// NCS and RAL — the notations that name a colour standard instead of RGB
    /// components. Both resolve to an approximate sRGB value.
    private static func standard(_ text: String) -> ColorLiteral? {
        if let ncs = ColorSystems.ncs(text) {
            return ColorLiteral(
                red: ncs.red,
                green: ncs.green,
                blue: ncs.blue,
                alpha: 1,
                source: text,
                origin: .ncs,
                label: ncs.label
            )
        }

        if let ral = ColorSystems.ral(text) {
            return ColorLiteral(
                red: ral.red,
                green: ral.green,
                blue: ral.blue,
                alpha: 1,
                source: text,
                origin: .ral,
                label: ral.label
            )
        }

        return nil
    }

    /// `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`. Bare digits only at six, which
    /// is where they are unambiguous in practice (`fe92f5`) and where the short
    /// forms are not (`cafe`, `beef`, `facade` are words).
    private static func hex(_ text: String) -> ColorLiteral? {
        var digits = text
        let hadHash = digits.hasPrefix("#")
        if hadHash {
            digits.removeFirst()
        }

        guard [3, 4, 6, 8].contains(digits.count),
              digits.allSatisfy(\.isHexDigit) else {
            return nil
        }
        guard hadHash || digits.count == 6 else { return nil }

        let characters = Array(digits.uppercased())

        func nibble(_ index: Int) -> Double {
            Double(Int(String(characters[index]), radix: 16) ?? 0) / 15
        }

        func byte(_ index: Int) -> Double {
            let pair = String(characters[index]) + String(characters[index + 1])
            return Double(Int(pair, radix: 16) ?? 0) / 255
        }

        let components: (Double, Double, Double, Double)
        if characters.count <= 4 {
            components = (
                nibble(0),
                nibble(1),
                nibble(2),
                characters.count == 4 ? nibble(3) : 1
            )
        } else {
            components = (
                byte(0),
                byte(2),
                byte(4),
                characters.count == 8 ? byte(6) : 1
            )
        }

        return ColorLiteral(
            red: components.0,
            green: components.1,
            blue: components.2,
            alpha: components.3,
            source: text,
            origin: .hex
        )
    }

    private static let functionNames: Set<String> = [
        "rgb", "rgba", "hsl", "hsla", "hsv", "hsva", "hsb", "hsba",
    ]

    private static func function(_ text: String) -> ColorLiteral? {
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else {
            return nil
        }

        let name = text[text.startIndex..<open]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard functionNames.contains(name) else { return nil }

        let inner = text[text.index(after: open)..<text.index(before: text.endIndex)]
        guard let parts = components(String(inner)),
              let alpha = alphaValue(parts.alpha),
              parts.channels.count == 3 else {
            return nil
        }

        if name.hasPrefix("rgb") {
            let values = parts.channels.compactMap(rgbChannel)
            guard values.count == 3 else { return nil }
            return ColorLiteral(
                red: values[0],
                green: values[1],
                blue: values[2],
                alpha: alpha,
                source: text,
                origin: .rgb
            )
        }

        guard let hue = hueValue(parts.channels[0]),
              let saturation = percentValue(parts.channels[1]),
              let third = percentValue(parts.channels[2]) else {
            return nil
        }

        if name.hasPrefix("hsl") {
            let rgb = fromHSL(hue: hue, saturation: saturation, lightness: third)
            return ColorLiteral(
                red: rgb.0,
                green: rgb.1,
                blue: rgb.2,
                alpha: alpha,
                source: text,
                origin: .hsl
            )
        }

        let rgb = fromHSV(hue: hue, saturation: saturation, value: third)
        return ColorLiteral(
            red: rgb.0,
            green: rgb.1,
            blue: rgb.2,
            alpha: alpha,
            source: text,
            origin: .hsv
        )
    }

    private struct Components {
        var channels: [String]
        var alpha: String?
    }

    /// Split the inside of `rgb(…)`/`hsl(…)` the three ways CSS allows:
    /// `a, b, c`, `a b c`, and either plus `/ alpha` (or a fourth comma value).
    private static func components(_ inner: String) -> Components? {
        let normalized = inner
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "/", with: " / ")
        var tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        if let slash = tokens.firstIndex(of: "/") {
            guard slash == tokens.count - 2 else { return nil }
            let alpha = tokens[slash + 1]
            tokens.removeSubrange(slash...)
            return Components(channels: tokens, alpha: alpha)
        }

        switch tokens.count {
        case 3:
            return Components(channels: tokens, alpha: nil)
        case 4:
            return Components(channels: Array(tokens.prefix(3)), alpha: tokens[3])
        default:
            return nil
        }
    }

    private static func rgbChannel(_ token: String) -> Double? {
        if token.hasSuffix("%") {
            guard let percent = Double(token.dropLast()), (0...100).contains(percent) else {
                return nil
            }
            return percent / 100
        }

        guard let value = Double(token), (0...255).contains(value) else { return nil }
        return value / 255
    }

    private static func alphaValue(_ token: String?) -> Double? {
        guard let token else { return 1 }

        if token.hasSuffix("%") {
            guard let percent = Double(token.dropLast()), (0...100).contains(percent) else {
                return nil
            }
            return percent / 100
        }

        guard let value = Double(token), (0...1).contains(value) else { return nil }
        return value
    }

    /// `43%`, `43` and `0.43` all mean 43 percent here; `0.43` only by virtue of
    /// being at most 1, which is the only reading that makes sense.
    private static func percentValue(_ token: String) -> Double? {
        var body = token
        let isPercent = body.hasSuffix("%")
        if isPercent {
            body.removeLast()
        }

        guard let value = Double(body), value.isFinite, value >= 0 else { return nil }
        let fraction = (isPercent || value > 1) ? value / 100 : value
        guard (0...1).contains(fraction) else { return nil }
        return fraction
    }

    private static func hueValue(_ token: String) -> Double? {
        var body = token.lowercased()
        for suffix in ["deg", "°"] where body.hasSuffix(suffix) {
            body.removeLast(suffix.count)
        }

        guard let value = Double(body), value.isFinite else { return nil }
        return value
    }

    /// `254, 146, 245` — the bare triplet a colour picker hands you.
    private static func triplet(_ text: String) -> ColorLiteral? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var values: [Double] = []
        for part in parts {
            let token = part.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty,
                  token.allSatisfy(\.isNumber),
                  let value = Int(token),
                  (0...255).contains(value) else {
                return nil
            }
            values.append(Double(value) / 255)
        }

        return ColorLiteral(
            red: values[0],
            green: values[1],
            blue: values[2],
            alpha: 1,
            source: text,
            origin: .rgb
        )
    }

    private static func named(_ text: String) -> ColorLiteral? {
        let key = text.lowercased()

        if key == "transparent" {
            return ColorLiteral(
                red: 0,
                green: 0,
                blue: 0,
                alpha: 0,
                source: text,
                origin: .named
            )
        }

        guard let packed = namedColors[key] else { return nil }
        return ColorLiteral(
            red: Double((packed >> 16) & 0xFF) / 255,
            green: Double((packed >> 8) & 0xFF) / 255,
            blue: Double(packed & 0xFF) / 255,
            alpha: 1,
            source: text,
            origin: .named
        )
    }

    // MARK: Conversions in

    private static func fromHSL(
        hue: Double,
        saturation: Double,
        lightness: Double
    ) -> (Double, Double, Double) {
        let h = normalizedHue(hue)
        guard saturation > 0 else { return (lightness, lightness, lightness) }

        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q

        func channel(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }

        return (channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
    }

    private static func fromHSV(
        hue: Double,
        saturation: Double,
        value: Double
    ) -> (Double, Double, Double) {
        let position = normalizedHue(hue) * 6
        let sector = Int(position.rounded(.down)) % 6
        let fraction = position - position.rounded(.down)

        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))

        switch sector {
        case 0: return (value, t, p)
        case 1: return (q, value, p)
        case 2: return (p, value, t)
        case 3: return (p, q, value)
        case 4: return (t, p, value)
        default: return (value, p, q)
        }
    }

    private static func normalizedHue(_ hue: Double) -> Double {
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        return (wrapped < 0 ? wrapped + 360 : wrapped) / 360
    }
}

// MARK: - Representations

extension ColorLiteral {
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    /// `#FE92F5`, or `#FE92F580` when it has alpha.
    var hex: String {
        let r = channel(red)
        let g = channel(green)
        let b = channel(blue)

        if alpha < 1 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, channel(alpha))
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// `rgb(254, 146, 245)` — what people usually paste into CSS.
    var rgb255: String {
        let r = channel(red)
        let g = channel(green)
        let b = channel(blue)

        guard alpha < 1 else { return "rgb(\(r), \(g), \(b))" }
        return "rgba(\(r), \(g), \(b), \(Self.decimal(alpha)))"
    }

    /// `rgb(0.996, 0.573, 0.961)` — what `Color(red:green:blue:)` and most
    /// graphics APIs actually take.
    var rgbUnit: String {
        let body = "\(Self.decimal(red, places: 3)), "
            + "\(Self.decimal(green, places: 3)), "
            + "\(Self.decimal(blue, places: 3))"

        guard alpha < 1 else { return "rgb(\(body))" }
        return "rgba(\(body), \(Self.decimal(alpha)))"
    }

    var hsl: String {
        let parts = hslComponents
        let body = "\(Self.degrees(parts.hue)), "
            + "\(Self.percent(parts.saturation)), "
            + "\(Self.percent(parts.lightness))"

        guard alpha < 1 else { return "hsl(\(body))" }
        return "hsla(\(body), \(Self.decimal(alpha)))"
    }

    var hsv: String {
        let parts = hsvComponents
        let body = "\(Self.degrees(parts.hue)), "
            + "\(Self.percent(parts.saturation)), "
            + "\(Self.percent(parts.value))"

        guard alpha < 1 else { return "hsv(\(body))" }
        return "hsva(\(body), \(Self.decimal(alpha)))"
    }

    /// WCAG relative luminance, 0…1.
    var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(red)
            + 0.7152 * linear(green)
            + 0.0722 * linear(blue)
    }

    var contrastWithWhite: Double {
        1.05 / (relativeLuminance + 0.05)
    }

    var contrastWithBlack: Double {
        (relativeLuminance + 0.05) / 0.05
    }

    /// The CSS colour this sits closest to, and whether it is an exact hit.
    var nearestName: (name: String, exact: Bool)? {
        let r = channel(red)
        let g = channel(green)
        let b = channel(blue)

        var best: (name: String, distance: Int)?
        for (name, packed) in Self.namedColors {
            let dr = Int((packed >> 16) & 0xFF) - r
            let dg = Int((packed >> 8) & 0xFF) - g
            let db = Int(packed & 0xFF) - b
            let distance = dr * dr + dg * dg + db * db

            guard let current = best else {
                best = (name, distance)
                continue
            }
            // Alphabetical tie-break, so the answer does not depend on the
            // dictionary's iteration order.
            if distance < current.distance
                || (distance == current.distance && name < current.name) {
                best = (name, distance)
            }
        }

        guard let best else { return nil }
        return (best.name, best.distance == 0)
    }

    /// `Color(red: 0.996, green: 0.573, blue: 0.961)` — paste straight into
    /// this app, or any SwiftUI one.
    var swiftUI: String {
        let body = "Color(red: \(Self.decimal(red, places: 3)), "
            + "green: \(Self.decimal(green, places: 3)), "
            + "blue: \(Self.decimal(blue, places: 3)))"

        guard alpha < 1 else { return body }
        return "\(body).opacity(\(Self.decimal(alpha)))"
    }

    /// NCS and RAL are standards, not RGB: what you see here is the closest a
    /// screen gets, so their hex is written with a `≈`.
    var isApproximate: Bool {
        origin == .ncs || origin == .ral
    }

    /// `Flame red`, when the notation carries a name.
    var name: String? {
        guard origin == .ral, let label else { return nil }
        let pieces = label.split(separator: " ", maxSplits: 2)
        return pieces.count == 3 ? String(pieces[2]) : nil
    }

    /// The row's second line: enough to recognise and paste, not a manual.
    var summary: String {
        var parts: [String] = []
        if let name {
            parts.append(name)
        }
        parts.append((isApproximate ? "≈" : "") + hex)
        parts.append(rgb255)
        if parts.count < 3 {
            parts.append(hsl)
        }
        return parts.joined(separator: " · ")
    }

    /// The tooltip: everything the row cannot fit.
    var tooltip: String {
        var lines: [String] = []

        if let label {
            lines.append(label)
        }
        lines.append("\(isApproximate ? "≈" : "")\(hex)  (\(origin.rawValue))")
        lines.append(rgb255)
        lines.append(rgbUnit)
        lines.append(hsl)
        lines.append(hsv)

        if let nearest = nearestName {
            lines.append(
                nearest.exact
                    ? "CSS name \(nearest.name)"
                    : "Nearest CSS name \(nearest.name)"
            )
        }

        // The one cross-reference the paint world actually asks for.
        if origin == .ncs, let ral = ColorSystems.nearestRAL(red: red, green: green, blue: blue) {
            lines.append("Nearest \(ral)")
        }

        lines.append(
            "Luminance \(Self.decimal(relativeLuminance))"
                + " · \(Self.decimal(contrastWithWhite)):1 on white"
                + " · \(Self.decimal(contrastWithBlack)):1 on black"
        )
        lines.append(swiftUI)

        if isApproximate {
            lines.append(
                origin == .ral
                    ? "Approximate — RAL names paint, not pixels"
                    : "Approximate — NCS describes perception, not pixels"
            )
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    private var hslComponents: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum

        guard delta > 0 else { return (0, 0, lightness) }

        let saturation = lightness > 0.5
            ? delta / (2 - maximum - minimum)
            : delta / (maximum + minimum)

        var hue: Double
        if maximum == red {
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        } else if maximum == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }

        return (hue * 60, saturation, lightness)
    }

    private var hsvComponents: (hue: Double, saturation: Double, value: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        guard maximum > 0 else { return (0, 0, 0) }
        guard delta > 0 else { return (0, 0, maximum) }

        let saturation = delta / maximum

        var hue: Double
        if maximum == red {
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        } else if maximum == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }

        return (hue * 60, saturation, maximum)
    }

    /// A 0…1 component as 0…255, rounded and clamped.
    private func channel(_ value: Double) -> Int {
        min(max(Int((value * 255).rounded()), 0), 255)
    }

    private static func degrees(_ value: Double) -> String {
        let rounded = Int(value.rounded()) % 360
        return "\(rounded < 0 ? rounded + 360 : rounded)"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Trimmed decimal: `0.5`, not `0.50`; `0`, not `0.000`.
    private static func decimal(_ value: Double, places: Int = 2) -> String {
        var text = String(format: "%.\(places)f", value)
        guard text.contains(".") else { return text }

        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text == "-0" ? "0" : text
    }

    /// The 148 CSS named colours (`grey`/`gray` and friends included).
    fileprivate static let namedColors: [String: UInt32] = [
        "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF, "aquamarine": 0x7FFFD4,
        "azure": 0xF0FFFF, "beige": 0xF5F5DC, "bisque": 0xFFE4C4, "black": 0x000000,
        "blanchedalmond": 0xFFEBCD, "blue": 0x0000FF, "blueviolet": 0x8A2BE2, "brown": 0xA52A2A,
        "burlywood": 0xDEB887, "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00,
        "chocolate": 0xD2691E, "coral": 0xFF7F50, "cornflowerblue": 0x6495ED, "cornsilk": 0xFFF8DC,
        "crimson": 0xDC143C, "cyan": 0x00FFFF, "darkblue": 0x00008B, "darkcyan": 0x008B8B,
        "darkgoldenrod": 0xB8860B, "darkgray": 0xA9A9A9, "darkgreen": 0x006400,
        "darkgrey": 0xA9A9A9, "darkkhaki": 0xBDB76B, "darkmagenta": 0x8B008B,
        "darkolivegreen": 0x556B2F, "darkorange": 0xFF8C00, "darkorchid": 0x9932CC,
        "darkred": 0x8B0000, "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F,
        "darkslateblue": 0x483D8B, "darkslategray": 0x2F4F4F, "darkslategrey": 0x2F4F4F,
        "darkturquoise": 0x00CED1, "darkviolet": 0x9400D3, "deeppink": 0xFF1493,
        "deepskyblue": 0x00BFFF, "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1E90FF,
        "firebrick": 0xB22222, "floralwhite": 0xFFFAF0, "forestgreen": 0x228B22,
        "fuchsia": 0xFF00FF, "gainsboro": 0xDCDCDC, "ghostwhite": 0xF8F8FF, "gold": 0xFFD700,
        "goldenrod": 0xDAA520, "gray": 0x808080, "green": 0x008000, "greenyellow": 0xADFF2F,
        "grey": 0x808080, "honeydew": 0xF0FFF0, "hotpink": 0xFF69B4, "indianred": 0xCD5C5C,
        "indigo": 0x4B0082, "ivory": 0xFFFFF0, "khaki": 0xF0E68C, "lavender": 0xE6E6FA,
        "lavenderblush": 0xFFF0F5, "lawngreen": 0x7CFC00, "lemonchiffon": 0xFFFACD,
        "lightblue": 0xADD8E6, "lightcoral": 0xF08080, "lightcyan": 0xE0FFFF,
        "lightgoldenrodyellow": 0xFAFAD2, "lightgray": 0xD3D3D3, "lightgreen": 0x90EE90,
        "lightgrey": 0xD3D3D3, "lightpink": 0xFFB6C1, "lightsalmon": 0xFFA07A,
        "lightseagreen": 0x20B2AA, "lightskyblue": 0x87CEFA, "lightslategray": 0x778899,
        "lightslategrey": 0x778899, "lightsteelblue": 0xB0C4DE, "lightyellow": 0xFFFFE0,
        "lime": 0x00FF00, "limegreen": 0x32CD32, "linen": 0xFAF0E6, "magenta": 0xFF00FF,
        "maroon": 0x800000, "mediumaquamarine": 0x66CDAA, "mediumblue": 0x0000CD,
        "mediumorchid": 0xBA55D3, "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371,
        "mediumslateblue": 0x7B68EE, "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC,
        "mediumvioletred": 0xC71585, "midnightblue": 0x191970, "mintcream": 0xF5FFFA,
        "mistyrose": 0xFFE4E1, "moccasin": 0xFFE4B5, "navajowhite": 0xFFDEAD, "navy": 0x000080,
        "oldlace": 0xFDF5E6, "olive": 0x808000, "olivedrab": 0x6B8E23, "orange": 0xFFA500,
        "orangered": 0xFF4500, "orchid": 0xDA70D6, "palegoldenrod": 0xEEE8AA,
        "palegreen": 0x98FB98, "paleturquoise": 0xAFEEEE, "palevioletred": 0xDB7093,
        "papayawhip": 0xFFEFD5, "peachpuff": 0xFFDAB9, "peru": 0xCD853F, "pink": 0xFFC0CB,
        "plum": 0xDDA0DD, "powderblue": 0xB0E0E6, "purple": 0x800080, "rebeccapurple": 0x663399,
        "red": 0xFF0000, "rosybrown": 0xBC8F8F, "royalblue": 0x4169E1, "saddlebrown": 0x8B4513,
        "salmon": 0xFA8072, "sandybrown": 0xF4A460, "seagreen": 0x2E8B57, "seashell": 0xFFF5EE,
        "sienna": 0xA0522D, "silver": 0xC0C0C0, "skyblue": 0x87CEEB, "slateblue": 0x6A5ACD,
        "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xFFFAFA, "springgreen": 0x00FF7F,
        "steelblue": 0x4682B4, "tan": 0xD2B48C, "teal": 0x008080, "thistle": 0xD8BFD8,
        "tomato": 0xFF6347, "turquoise": 0x40E0D0, "violet": 0xEE82EE, "wheat": 0xF5DEB3,
        "white": 0xFFFFFF, "whitesmoke": 0xF5F5F5, "yellow": 0xFFFF00, "yellowgreen": 0x9ACD32,
    ]
}
