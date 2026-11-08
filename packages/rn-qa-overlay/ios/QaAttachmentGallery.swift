import AVKit
import ImageIO
import SwiftUI

struct QaAttachmentGallery: View {
  @ObservedObject var draft: QaDraft
  let onClose: () -> Void
  @State private var selection: UUID

  init(draft: QaDraft, initial: UUID, onClose: @escaping () -> Void) {
    self.draft = draft
    self.onClose = onClose
    _selection = State(initialValue: initial)
  }

  var body: some View {
    NavigationStack {
      TabView(selection: $selection) {
        ForEach(draft.attachments) { attachment in
          QaAssetPage(attachment: attachment, active: selection == attachment.id,
            position: (draft.attachments.firstIndex(where: { $0.id == attachment.id }) ?? 0) + 1, count: draft.attachments.count)
            .tag(attachment.id)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .background(Color.black)
      .accessibilityIdentifier("qa-overlay.preview")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Back", systemImage: "chevron.left", action: onClose)
            .labelStyle(.iconOnly).accessibilityIdentifier("qa-overlay.preview.close")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Remove", systemImage: "trash", role: .destructive, action: removeSelected)
              .disabled(QaLinearSession.shared.locked)
          } label: { Label("More", systemImage: "ellipsis") }
            .accessibilityIdentifier("qa-overlay.preview.more")
        }
      }
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
  }

  private func removeSelected() {
    guard !QaLinearSession.shared.locked,
      let index = draft.attachments.firstIndex(where: { $0.id == selection }) else { return }
    let attachment = draft.attachments[index]
    let remaining = draft.attachments.filter { $0.id != selection }
    if remaining.isEmpty { onClose() }
    else { selection = remaining[min(index, remaining.count - 1)].id }
    draft.remove(attachment)
  }
}

private struct QaAssetPage: View {
  let attachment: QaAttachment
  let active: Bool
  let position: Int
  let count: Int
  @State private var image: UIImage?
  @State private var player: AVPlayer?
  @State private var failed = false

  var body: some View {
    Group {
      if attachment.isVideo {
        if let player { VideoPlayer(player: player) }
        else { ProgressView() }
      } else if let image {
        Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Image \(position) of \(count)")
      } else if failed {
        Text("This image could not be opened.").foregroundStyle(.white)
      } else { ProgressView() }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
    .task(id: active) {
      if attachment.isVideo {
        guard active else { player?.pause(); return }
        if player == nil { player = AVPlayer(url: attachment.url) }
        player?.play()
      } else if image == nil {
        let url = attachment.url
        image = await Task.detached(priority: .userInitiated) {
          guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 4096,
              kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { return nil as UIImage? }
          return UIImage(cgImage: cgImage)
        }.value
        failed = image == nil
      }
    }
    .onDisappear { player?.pause() }
  }
}
