import Foundation
import Vision

struct OCRLine {
  let text: String
  let left: CGFloat
  let top: CGFloat
  let height: CGFloat
}

enum OCRCaptureError: LocalizedError {
  case missingImagePath
  case unreadableImage(String)

  var errorDescription: String? {
    switch self {
    case .missingImagePath:
      return "Expected a screenshot path argument."
    case let .unreadableImage(path):
      return "Could not read screenshot at \(path)."
    }
  }
}

func sortedOCRLines(from results: [VNRecognizedTextObservation]) -> [OCRLine] {
  results
    .compactMap { observation -> OCRLine? in
      guard let candidate = observation.topCandidates(1).first else {
        return nil
      }

      let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        return nil
      }

      let box = observation.boundingBox
      return OCRLine(
        text: text,
        left: box.origin.x,
        top: box.origin.y + box.height,
        height: box.height
      )
    }
    .sorted { lhs, rhs in
      let yDelta = abs(lhs.top - rhs.top)
      if yDelta > max(lhs.height, rhs.height) * 0.35 {
        return lhs.top > rhs.top
      }
      return lhs.left < rhs.left
    }
}

func renderedText(from lines: [OCRLine]) -> String {
  var rendered: [String] = []
  var previous: OCRLine?

  for line in lines {
    if let previous {
      let gap = previous.top - line.top
      let threshold = max(previous.height, line.height) * 1.6
      if gap > threshold {
        rendered.append("")
      }
    }

    rendered.append(line.text)
    previous = line
  }

  return rendered.joined(separator: "\n")
}

func recognizeText() throws -> String {
  guard CommandLine.arguments.count >= 2 else {
    throw OCRCaptureError.missingImagePath
  }

  let imagePath = CommandLine.arguments[1]
  let imageURL = URL(fileURLWithPath: imagePath)

  guard FileManager.default.fileExists(atPath: imagePath) else {
    throw OCRCaptureError.unreadableImage(imagePath)
  }

  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = true
  if #available(macOS 13.0, *) {
    request.automaticallyDetectsLanguage = true
  }

  let handler = VNImageRequestHandler(url: imageURL)
  try handler.perform([request])

  let lines = sortedOCRLines(from: request.results ?? [])
  return renderedText(from: lines)
}

do {
  let output = try recognizeText()
  FileHandle.standardOutput.write(Data(output.utf8))
} catch {
  let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  FileHandle.standardError.write(Data((message + "\n").utf8))
  Foundation.exit(1)
}
