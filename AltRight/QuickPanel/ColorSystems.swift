import Foundation

/// NCS and RAL — the two colour standards a paint chip arrives as text.
///
/// Neither is defined in RGB: NCS describes perception (“50% blackness, 10%
/// chromaticness, hue Y 90% of the way to R”), RAL names physical swatches. Both
/// therefore convert to an *approximate* sRGB value — enough to recognise a
/// colour in the list, not enough to match paint, which is why those rows print
/// a `≈` before the hex.
enum ColorSystems {
    /// An approximate sRGB colour plus the notation that produced it.
    struct Conversion {
        let red: Double
        let green: Double
        let blue: Double

        /// Normalised for display: `NCS S 1050-Y90R`, `RAL 3000 Flame red`.
        let label: String
    }

    // MARK: - NCS

    /// `NCS S 1050-Y90R`, `S 1050-Y90R`, `S1050-Y90R`, `1050-Y90R`, `S 1000-N`.
    /// The hue is one of the four elementary colours (Y, R, B, G), optionally
    /// with the percentage towards the next one in the NCS circle (Y→R→B→G→Y),
    /// or `N` for a neutral.
    private static let ncsPattern = try? NSRegularExpression(
        pattern: #"\A(?:NCS\s*)?(?:S\s*)?(\d{2})(\d{2})-(N|[YRGB](?:\d{2}[YRGB])?)\z"#,
        options: [.caseInsensitive]
    )

    private static let elementaryHues: [Character] = ["Y", "R", "B", "G"]

    static func ncs(_ text: String) -> Conversion? {
        guard let regex = ncsPattern,
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ) else {
            return nil
        }

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }

        guard let blacknessText = group(1),
              let chromaticnessText = group(2),
              let hueText = group(3)?.uppercased(),
              let blackness = Int(blacknessText),
              let chromaticness = Int(chromaticnessText),
              blackness + chromaticness <= 100 else {
            return nil
        }

        // Neutrals have no hue and no chromaticness; anything else with `-N`
        // is a typo, not a colour.
        if hueText == "N" {
            guard chromaticness == 0 else { return nil }
            let grey = 1 - Double(blackness) / 100
            return Conversion(
                red: grey,
                green: grey,
                blue: grey,
                label: "NCS S \(blacknessText)\(chromaticnessText)-N"
            )
        }

        let hue = Array(hueText)
        guard let base = hue.first, elementaryHues.contains(base) else { return nil }

        var percent = 0.0
        if hue.count > 1 {
            // Two-letter hues are only written with the percentage towards the
            // neighbour in the circle: Y90R, B10G — never Y90B.
            guard hue.count == 4,
                  let towards = hue.last,
                  elementaryHues.contains(towards),
                  towards == successor(of: base),
                  let value = Int(String(hue[1...2])),
                  (1...99).contains(value) else {
                return nil
            }
            percent = Double(value)
        }

        let rgb = components(
            blackness: Double(blackness),
            chromaticness: Double(chromaticness),
            base: base,
            percent: percent
        )

        return Conversion(
            red: rgb.0,
            green: rgb.1,
            blue: rgb.2,
            label: "NCS S \(blacknessText)\(chromaticnessText)-\(hueText)"
        )
    }

    private static func successor(of hue: Character) -> Character? {
        guard let index = elementaryHues.firstIndex(of: hue) else { return nil }
        return elementaryHues[(index + 1) % elementaryHues.count]
    }

    /// The published NCS-to-RGB approximation: each elementary hue contributes
    /// a strength curve, the mean pulls the result towards grey by
    /// chromaticness, and blackness scales what is left.
    private static func components(
        blackness: Double,
        chromaticness: Double,
        base: Character,
        percent: Double
    ) -> (Double, Double, Double) {
        let red = redStrength(base: base, percent: percent)
        let green = greenStrength(base: base, percent: percent)
        let blue = blueStrength(base: base, percent: percent)

        let grey = (red + green + blue) / 3
        let desaturation = (100 - chromaticness) / 100
        let r = (grey - red) * desaturation + red
        let g = (grey - green) * desaturation + green
        let b = (grey - blue) * desaturation + blue

        let top = max(r, g, b)
        guard top > 0 else { return (0, 0, 0) }

        // Blackness is scaled the way the NCS 2nd edition atlas was fitted;
        // the raw percentage alone would make 100% blackness pure black.
        let darkness = (100 - (1.05 * blackness - 5.25)) / 100
        let scale = darkness / top

        return (clamp(r * scale), clamp(g * scale), clamp(b * scale))
    }

    private static func redStrength(base: Character, percent: Double) -> Double {
        switch base {
        case "Y":
            guard percent > 60 else { return 1 }
            return curve(14884 - pow(percent - 60, 2), 22)
        case "R":
            guard percent <= 80 else { return 0 }
            return curve(14884 - pow(percent + 40, 2), 22)
        case "G":
            return curve(33800 - pow(percent - 170, 2), 70)
        default:
            return 0
        }
    }

    private static func blueStrength(base: Character, percent: Double) -> Double {
        switch base {
        case "Y":
            guard percent > 80 else { return 0 }
            return (104 - curveRoot(11236 - pow(percent - 80 + 20.5, 2))) / 100
        case "R":
            if percent <= 60 {
                return (104 - curveRoot(11236 - pow(percent + 40.5, 2))) / 100
            }
            return curve(10000 - pow(percent - 120, 2), 10)
        case "B":
            guard percent > 80 else {
                return curve(10000 - pow(percent - 20, 2), 10)
            }
            return (122 - curveRoot(19881 - pow(percent - 211, 2))) / 100
        case "G":
            guard percent <= 40 else { return 0 }
            return (122 - curveRoot(19881 - pow(percent - 111, 2))) / 100
        default:
            return 0
        }
    }

    private static func greenStrength(base: Character, percent: Double) -> Double {
        switch base {
        case "Y":
            return (85 - 0.85 * percent) / 100
        case "R":
            guard percent > 60 else { return 0 }
            return (67.5 - curveRoot(5776 - pow(percent - 25, 2))) / 100
        case "B":
            guard percent <= 60 else { return 0.9 }
            return (6.5 + curveRoot(7044.5 - pow(percent - 68.5, 2))) / 100
        case "G":
            guard percent > 60 else { return 0.9 }
            return (90 - (percent - 60) / 8) / 100
        default:
            return 0
        }
    }

    private static func curve(_ radicand: Double, _ offset: Double) -> Double {
        (curveRoot(radicand) - offset) / 100
    }

    /// `sqrt` of a radicand that the fitted curves can push slightly below
    /// zero at the notation's edges.
    private static func curveRoot(_ radicand: Double) -> Double {
        radicand > 0 ? radicand.squareRoot() : 0
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: - RAL

    /// `RAL 3000`, `RAL Classic 3000`, `RAL3000`. RAL Design (`RAL 210 60 30`)
    /// is a different, CIELAB-based system and is not handled.
    private static let ralPattern = try? NSRegularExpression(
        pattern: #"\A(?:RAL\s*(?:CLASSIC\s*)?)(\d{4})\z"#,
        options: [.caseInsensitive]
    )

    static func ral(_ text: String) -> Conversion? {
        guard let regex = ralPattern,
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let code = String(text[range])
        guard let entry = ralClassic[code] else { return nil }

        return Conversion(
            red: Double((entry.hex >> 16) & 0xFF) / 255,
            green: Double((entry.hex >> 8) & 0xFF) / 255,
            blue: Double(entry.hex & 0xFF) / 255,
            label: "RAL \(code) \(entry.name)"
        )
    }

    /// The closest RAL Classic swatch — the useful cross-reference when the copy
    /// is an NCS notation and the painter thinks in RAL.
    ///
    /// Compared in CIELAB, not RGB: plain channel distance happily calls a pale
    /// turquoise the nearest thing to a sky blue.
    static func nearestRAL(red: Double, green: Double, blue: Double) -> String? {
        let target = lab(red: red, green: green, blue: blue)

        var best: (code: String, name: String, distance: Double)?
        for (code, entry) in ralClassic {
            let candidate = lab(
                red: Double((entry.hex >> 16) & 0xFF) / 255,
                green: Double((entry.hex >> 8) & 0xFF) / 255,
                blue: Double(entry.hex & 0xFF) / 255
            )

            let dl = candidate.0 - target.0
            let da = candidate.1 - target.1
            let db = candidate.2 - target.2
            let distance = dl * dl + da * da + db * db

            guard let current = best else {
                best = (code, entry.name, distance)
                continue
            }
            if distance < current.distance
                || (distance == current.distance && code < current.code) {
                best = (code, entry.name, distance)
            }
        }

        guard let best else { return nil }
        return "RAL \(best.code) \(best.name)"
    }

    /// sRGB → CIELAB (D65).
    private static func lab(
        red: Double,
        green: Double,
        blue: Double
    ) -> (Double, Double, Double) {
        func linear(_ value: Double) -> Double {
            value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        let r = linear(red)
        let g = linear(green)
        let b = linear(blue)

        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

        func curve(_ value: Double) -> Double {
            value > 0.008856
                ? pow(value, 1.0 / 3)
                : 7.787 * value + 16.0 / 116
        }

        let fx = curve(x)
        let fy = curve(y)
        let fz = curve(z)

        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// RAL Classic: 217 swatches, sRGB approximations of physical samples.
    private static let ralClassic: [String: (hex: UInt32, name: String)] = [
    "1000": (0xCDBA88, "Green beige"), "1001": (0xD0B084, "Beige"),
    "1002": (0xD2AA6D, "Sand yellow"), "1003": (0xF9A900, "Signal yellow"),
    "1004": (0xE49E00, "Golden yellow"), "1005": (0xCB8F00, "Honey yellow"),
    "1006": (0xE19000, "Maize yellow"), "1007": (0xE88C00, "Daffodil yellow"),
    "1011": (0xAF8050, "Brown beige"), "1012": (0xDDAF28, "Lemon yellow"),
    "1013": (0xE3D9C7, "Oyster white"), "1014": (0xDDC49B, "Ivory"),
    "1015": (0xE6D2B5, "Light ivory"), "1016": (0xF1DD39, "Sulfur yellow"),
    "1017": (0xF6A951, "Saffron yellow"), "1018": (0xFACA31, "Zinc yellow"),
    "1019": (0xA48F7A, "Grey beige"), "1020": (0xA08F65, "Olive yellow"),
    "1021": (0xF6B600, "Colza yellow"), "1023": (0xF7B500, "Traffic yellow"),
    "1024": (0xBA8F4C, "Ochre yellow"), "1026": (0xFFFF00, "Luminous yellow"),
    "1027": (0xA77F0F, "Curry"), "1028": (0xFF9C00, "Melon yellow"),
    "1032": (0xE2A300, "Broom yellow"), "1033": (0xF99A1D, "Dahlia yellow"),
    "1034": (0xEB9C52, "Pastel yellow"), "1035": (0x8F8370, "Pearl beige"),
    "1036": (0x806440, "Pearl gold"), "1037": (0xF09200, "Sun yellow"),
    "2000": (0xDA6E00, "Yellow orange"), "2001": (0xBA481C, "Red orange"),
    "2002": (0xBF3922, "Vermilion"), "2003": (0xF67829, "Pastel orange"),
    "2004": (0xE25304, "Pure orange"), "2005": (0xFF4D08, "Luminous orange"),
    "2007": (0xFFB200, "Luminous bright orange"), "2008": (0xEC6B22, "Bright red orange"),
    "2009": (0xDE5308, "Traffic orange"), "2010": (0xD05D29, "Signal orange"),
    "2011": (0xE26E0F, "Deep orange"), "2012": (0xD5654E, "Salmon orange"),
    "2013": (0x923E25, "Pearl orange"), "2017": (0xFC5500, "RAL orange"),
    "3000": (0xA72920, "Flame red"), "3001": (0x9B2423, "Signal red"),
    "3002": (0x9B2321, "Carmine red"), "3003": (0x861A22, "Ruby red"),
    "3004": (0x6B1C23, "Purple red"), "3005": (0x59191F, "Wine red"),
    "3007": (0x3E2022, "Black red"), "3009": (0x6D342D, "Oxide red"),
    "3011": (0x782423, "Brown red"), "3012": (0xC5856D, "Beige red"),
    "3013": (0x972E25, "Tomato red"), "3014": (0xCB7375, "Antique pink"),
    "3015": (0xD8A0A6, "Light pink"), "3016": (0xA63D30, "Coral red"),
    "3017": (0xCA555D, "Rose"), "3018": (0xC63F4A, "Strawberry red"),
    "3020": (0xBB1F11, "Traffic red"), "3022": (0xCF6955, "Salmon pink"),
    "3024": (0xFF2D21, "Luminous red"), "3026": (0xFF2A1C, "Luminous bright red"),
    "3027": (0xAB273C, "Raspberry red"), "3028": (0xCC2C24, "Pure red"),
    "3031": (0xA63437, "Orient red"), "3032": (0x701D24, "Pearl ruby red"),
    "3033": (0xA53A2E, "Pearl pink"), "4001": (0x816183, "Red lilac"),
    "4002": (0x8D3C4B, "Red violet"), "4003": (0xC4618C, "Heather violet"),
    "4004": (0x651E38, "Claret violet"), "4005": (0x76689A, "Blue lilac"),
    "4006": (0x903373, "Traffic purple"), "4007": (0x47243C, "Purple violet"),
    "4008": (0x844C82, "Signal violet"), "4009": (0x9D8692, "Pastel violet"),
    "4010": (0xBB4077, "Telemagenta"), "4011": (0x6E6387, "Pearl violet"),
    "4012": (0x6A6B7F, "Pearl blackberry"), "5000": (0x304F6E, "Violet blue"),
    "5001": (0x0E4C64, "Green blue"), "5002": (0x00387A, "Ultramarine blue"),
    "5003": (0x1F3855, "Sapphire blue"), "5004": (0x191E28, "Black blue"),
    "5005": (0x005387, "Signal blue"), "5007": (0x376B8C, "Brillant blue"),
    "5008": (0x2B3A44, "Grey blue"), "5009": (0x215F78, "Azure blue"),
    "5010": (0x004F7C, "Gentian blue"), "5011": (0x1A2B3C, "Steel blue"),
    "5012": (0x0089B6, "Light blue"), "5013": (0x193153, "Cobalt blue"),
    "5014": (0x637D96, "Pigeon blue"), "5015": (0x007CAF, "Sky blue"),
    "5017": (0x005B8C, "Traffic blue"), "5018": (0x048B8C, "Turquoise blue"),
    "5019": (0x005E83, "Capri blue"), "5020": (0x00414B, "Ocean blue"),
    "5021": (0x007577, "Water blue"), "5022": (0x222D5A, "Night blue"),
    "5023": (0x41698C, "Distant blue"), "5024": (0x6093AC, "Pastel blue"),
    "5025": (0x20697C, "Pearl gentian blue"), "5026": (0x0F3052, "Pearl night blue"),
    "6000": (0x3C7460, "Patina green"), "6001": (0x366735, "Emerald green"),
    "6002": (0x325928, "Leaf green"), "6003": (0x50533C, "Olive green"),
    "6004": (0x024442, "Blue green"), "6005": (0x114232, "Moss green"),
    "6006": (0x3C392E, "Grey olive"), "6007": (0x2C3222, "Bottle green"),
    "6008": (0x36342A, "Brown green"), "6009": (0x27352A, "Fir green"),
    "6010": (0x4D6F39, "Grass green"), "6011": (0x6B7C59, "Reseda green"),
    "6012": (0x2F3D3A, "Black green"), "6013": (0x7C765A, "Reed green"),
    "6014": (0x474135, "Yellow olive"), "6015": (0x3D3D36, "Black olive"),
    "6016": (0x00694C, "Turquoise green"), "6017": (0x587F40, "May green"),
    "6018": (0x60993B, "Yellow green"), "6019": (0xB9CEAC, "Pastel green"),
    "6020": (0x37422F, "Chrome green"), "6021": (0x8A9977, "Pale green"),
    "6022": (0x3A3327, "Olive drab"), "6024": (0x008351, "Traffic green"),
    "6025": (0x5E6E3B, "Fern green"), "6026": (0x005F4E, "Opal green"),
    "6027": (0x7EBAB5, "Light green"), "6028": (0x315442, "Pine green"),
    "6029": (0x006F3D, "Mint green"), "6031": (0x495746, "Bronze green"),
    "6032": (0x237F52, "Signal green"), "6033": (0x45877F, "Mint turquoise"),
    "6034": (0x7AADAC, "Pastel turquoise"), "6035": (0x194D25, "Pearl green"),
    "6036": (0x04574B, "Pearl opal green"), "6037": (0x008B29, "Pure green"),
    "6038": (0x00B51B, "Luminous green"), "6039": (0xB3C43E, "Fibrous green"),
    "7000": (0x7A888E, "Squirrel grey"), "7001": (0x8C979C, "Silver grey"),
    "7002": (0x817863, "Olive grey"), "7003": (0x797669, "Moss grey"),
    "7004": (0x9A9B9B, "Signal grey"), "7005": (0x6B6E6B, "Mouse grey"),
    "7006": (0x766A5E, "Beige grey"), "7008": (0x745F3D, "Khaki grey"),
    "7009": (0x5D6058, "Green grey"), "7010": (0x585C56, "Tarpaulin grey"),
    "7011": (0x52595D, "Iron grey"), "7012": (0x575D5E, "Basalt grey"),
    "7013": (0x575044, "Brown grey"), "7015": (0x4F5358, "Slate grey"),
    "7016": (0x383E42, "Anthracite grey"), "7021": (0x2F3234, "Black grey"),
    "7022": (0x4C4A44, "Umbra grey"), "7023": (0x808076, "Concrete grey"),
    "7024": (0x45494E, "Graphite grey"), "7026": (0x374345, "Granite grey"),
    "7030": (0x928E85, "Stone grey"), "7031": (0x5B686D, "Blue grey"),
    "7032": (0xB5B0A1, "Pebble grey"), "7033": (0x7F8274, "Cement grey"),
    "7034": (0x92886F, "Yellow grey"), "7035": (0xC5C7C4, "Light grey"),
    "7036": (0x979392, "Platinum grey"), "7037": (0x7A7B7A, "Dusty grey"),
    "7038": (0xB0B0A9, "Agate grey"), "7039": (0x6B665E, "Quartz grey"),
    "7040": (0x989EA1, "Window grey"), "7042": (0x8E9291, "Traffic grey A"),
    "7043": (0x4F5250, "Traffic grey B"), "7044": (0xB7B3A8, "Silk grey"),
    "7045": (0x8D9295, "Telegrey 1"), "7046": (0x7E868A, "Telegrey 2"),
    "7047": (0xC8C8C7, "Telegrey 4"), "7048": (0x817B73, "Pearl mouse grey"),
    "8000": (0x89693F, "Green brown"), "8001": (0x9D622B, "Ochre brown"),
    "8002": (0x794D3E, "Signal brown"), "8003": (0x7E4B27, "Clay brown"),
    "8004": (0x8D4931, "Copper brown"), "8007": (0x70462B, "Fawn brown"),
    "8008": (0x724A25, "Olive brown"), "8011": (0x5A3827, "Nut brown"),
    "8012": (0x66332B, "Red brown"), "8014": (0x4A3526, "Sepia brown"),
    "8015": (0x5E2F26, "Chestnut brown"), "8016": (0x4C2B20, "Mahogany brown"),
    "8017": (0x442F29, "Chocolate brown"), "8019": (0x3D3635, "Grey brown"),
    "8022": (0x1A1719, "Black brown"), "8023": (0xA45729, "Orange brown"),
    "8024": (0x795038, "Beige brown"), "8025": (0x755847, "Pale brown"),
    "8028": (0x513A2A, "Terra brown"), "8029": (0x7F4031, "Pearl copper"),
    "9001": (0xE9E0D2, "Cream"), "9002": (0xD6D5CB, "Grey white"),
    "9003": (0xECECE7, "Signal white"), "9004": (0x2B2B2C, "Signal black"),
    "9005": (0x0E0E10, "Jet black"), "9006": (0xA1A1A0, "White aluminium"),
    "9007": (0x868581, "Grey aluminium"), "9010": (0xF1EDE1, "Pure white"),
    "9011": (0x27292B, "Graphite black"), "9012": (0xF8F2E1, "Cleanroom white"),
    "9016": (0xF1F1EA, "Traffic white"), "9017": (0x29292A, "Traffic black"),
    "9018": (0xC8CBC4, "Papyrus white"), "9022": (0x858583, "Pearl light grey"),
    "9023": (0x787B7A, "Pearl dark grey"),
    ]
}
