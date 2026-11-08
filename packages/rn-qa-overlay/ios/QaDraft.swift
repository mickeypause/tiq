import AVFoundation
import ImageIO
import SwiftUI

struct QaAttachment: Identifiable {
  let id = UUID()
  let url: URL
  let isVideo: Bool
  let thumbnail: UIImage?
}

@MainActor
final class QaDraft: ObservableObject {
  @Published var title = ""
  @Published var description = ""
  @Published var attachments: [QaAttachment] = []
  @Published var error: String?
  @Published var isImporting = false
  let team = Bundle.main.object(forInfoDictionaryKey: "RnQaOverlayTeam") as? String ?? "Product"
  var hasContent: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }
  static let maxBytes: Int64 = 100 * 1024 * 1024

  static func newFile(extension suffix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rn-qa-overlay", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
  }

  func addOwnedFile(_ url: URL, video: Bool) {
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size > 0, size <= Self.maxBytes else {
        try? FileManager.default.removeItem(at: url)
        error = "Choose a file smaller than 100 MB."
        return
      }
      let thumbnail: UIImage?
      if video {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        thumbnail = (try? generator.copyCGImage(at: .zero, actualTime: nil)).map { UIImage(cgImage: $0) }
      } else {
        // Downsample previews instead of retaining full-resolution camera images.
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        thumbnail = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) }.map { UIImage(cgImage: $0) }
      }
      attachments.append(QaAttachment(url: url, isVideo: video, thumbnail: thumbnail))
    } catch { self.error = error.localizedDescription }
  }

  func remove(_ attachment: QaAttachment) {
    attachments.removeAll { $0.id == attachment.id }
    try? FileManager.default.removeItem(at: attachment.url)
  }

  func discard() {
    for attachment in attachments { try? FileManager.default.removeItem(at: attachment.url) }
    attachments = []
    title = ""
    description = ""
  }
}
