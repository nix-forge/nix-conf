// Run on the configured Mac after Home Manager activation: swift check_coretext.swift
import AppKit
import CoreText

// CI registers only the tested files for this process. With no argument this
// checks the real, activated user installation on the Mac.
var selectedFamilies: [String] = []
if CommandLine.arguments.count > 1 {
  let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
  let decoded = try JSONSerialization.jsonObject(with: data)
  guard let report = decoded as? [String: Any],
    let selections = report["selection"] as? [String: [String: Any]]
  else {
    fatalError("Selection report has an invalid schema")
  }
  let paths = Set(
    selections.filter { !$0.key.hasPrefix("emoji:") }.values.compactMap { $0["file"] as? String })
  for path in paths {
    var error: Unmanaged<CFError>?
    guard CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error)
    else {
      fatalError("Font registration failed for \(path): \(String(describing: error))")
    }
  }
  for prefix in ["sans-serif:", "serif:", "monospace:"] {
    for (key, selection) in selections where key.hasPrefix(prefix) {
      guard let family = selection["family"] as? String else {
        fatalError("Selection \(key) has no family")
      }
      if !selectedFamilies.contains(family) {
        selectedFamilies.append(family)
      }
    }
  }
}

guard let systemFont = CTFontCreateUIFontForLanguage(.system, 24, nil) else {
  fatalError("Core Text did not provide a system font")
}
let families =
  selectedFamilies.isEmpty
  ? [CTFontCopyFamilyName(systemFont) as String]
  : selectedFamilies
for family in families {
  let font = CTFontCreateWithName(family as CFString, 24, nil)
  let actual = CTFontCopyFamilyName(font) as String
  guard actual == family else {
    fatalError("Requested \(family), Core Text selected \(actual)")
  }
  print("Core Text: \(actual)")
}
let emojiFont = CTFontCreateForString(systemFont, "😀" as CFString, CFRange(location: 0, length: 1))
let emojiFamily = CTFontCopyFamilyName(emojiFont) as String
guard !emojiFamily.isEmpty else {
  fatalError("Core Text did not provide a family for emoji fallback")
}
print("Core Text emoji cascade: \(emojiFamily)")
let sample = "0123456789 café العربية 日本語 😀"
guard let sampleFont = NSFont(name: families[0], size: 32) else {
  fatalError("\(families[0]) is unavailable after successful family validation")
}
let text = NSAttributedString(string: sample, attributes: [.font: sampleFont])
let line = CTLineCreateWithAttributedString(text)
guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else {
  fatalError("Core Text returned an invalid glyph-run collection")
}
for run in runs {
  let count = CTRunGetGlyphCount(run)
  var glyphs = [CGGlyph](repeating: 0, count: count)
  CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
  guard !glyphs.contains(0) else { fatalError("Core Text selected a missing glyph") }
}
print("Native multilingual and emoji shaping passed")
