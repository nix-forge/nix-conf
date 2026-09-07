// Run on the configured Mac after Home Manager activation: swift check_coretext.swift
import AppKit
import CoreText

// CI registers only the tested files for this process. With no argument this
// checks the real, activated user installation on the Mac.
if CommandLine.arguments.count > 1 {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let report = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let selections = report["selection"] as! [String: [String: Any]]
    let paths = Set(selections.filter { !$0.key.hasPrefix("emoji:") }.values.compactMap { $0["file"] as? String })
    for path in paths {
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error) else {
            fatalError("Font registration failed for \(path): \(String(describing: error))")
        }
    }
}
let families = ["Inter", "Literata", "MonaspiceNe Nerd Font", "Apple Color Emoji"]
for family in families {
    let font = CTFontCreateWithName(family as CFString, 24, nil)
    let actual = CTFontCopyFamilyName(font) as String
    guard actual == family else {
        fatalError("Requested \(family), Core Text selected \(actual)")
    }
    print("Core Text: \(actual)")
}
let sample = "0123456789 café العربية 日本語 😀"
let text = NSAttributedString(string: sample, attributes: [.font: NSFont(name: "Inter", size: 32)!])
let line = CTLineCreateWithAttributedString(text)
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
    guard !glyphs.contains(0) else { fatalError("Core Text selected a missing glyph") }
}
print("Native multilingual and emoji shaping passed")
