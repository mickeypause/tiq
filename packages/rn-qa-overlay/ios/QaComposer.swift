import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct QaComposer: View {
  let host: QaOverlayHost
  @ObservedObject var draft: QaDraft
  let dismiss: () -> Void
  @ObservedObject private var linear = QaLinearSession.shared
  private enum Field { case title, description }
  @FocusState private var focusedField: Field?
  @State private var fieldBeforePresentation: Field?
  @ScaledMetric(relativeTo: .title2) private var titleSize = 24
  @ScaledMetric(relativeTo: .body) private var toolbarIconSize = 20
  @ScaledMetric(relativeTo: .subheadline) private var teamFontSize = 15
  @State private var closeConfirmation = false
  @State private var initialFocusRequested = false
  @State private var gallery = false
  @State private var camera: CameraMode?
  @State private var preview: QaAttachment?
  @Namespace private var previewTransition
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    NavigationStack {
      Group {
      if !linear.authenticated {
        VStack(spacing: 20) {
          Text("Connect to Linear").font(.title2.bold())
          Text(linear.configured ? "Sign in to create issues in your workspace." : "Configure the Linear Client ID and redirect URI in the Expo plugin to enable reporting.").foregroundStyle(.secondary).multilineTextAlignment(.center)
          if linear.configured { Button("Sign in to Linear") { Task { await linear.signIn() } }.buttonStyle(.borderedProminent).disabled(linear.busy) }
        }.padding(24).disabled(linear.locked).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          TextField("Issue title", text: $draft.title, prompt: Text("Issue title").foregroundColor(.secondary), axis: .vertical)
            .font(.system(size: titleSize, weight: .bold)).focused($focusedField, equals: .title)
            .accessibilityLabel("Issue title").accessibilityIdentifier("qa-overlay.title")
          TextField("Description…", text: $draft.description, prompt: Text("Description…").foregroundColor(.secondary), axis: .vertical)
            .font(.body).focused($focusedField, equals: .description).lineLimit(5...20).accessibilityLabel("Description").accessibilityIdentifier("qa-overlay.description")
          if draft.isImporting { ProgressView("Importing attachment…") }
          if !draft.attachments.isEmpty {
            ScrollView(.horizontal) {
              HStack(spacing: 12) {
                ForEach(draft.attachments) { attachment in
                  ZStack(alignment: .topTrailing) {
                    Button { fieldBeforePresentation = focusedField; focusedField = nil; preview = attachment } label: {
                      ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                        if let thumbnail = attachment.thumbnail {
                          Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 208, height: 156).clipped()
                        }
                        if attachment.isVideo { Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white) }
                      }.frame(width: 208, height: 156).clipShape(RoundedRectangle(cornerRadius: 12))
                    }.modifier(QaPreviewSource(id: attachment.id, namespace: previewTransition, reduceMotion: reduceMotion))
                      .accessibilityLabel(attachment.isVideo ? "Preview video" : "Preview image")
                    Button(role: .destructive) { draft.remove(attachment) } label: {
                      Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white).frame(width: 20, height: 20)
                        .background(Color(uiColor: .systemGray).opacity(0.85), in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).offset(x: 8, y: -8)
                      .accessibilityLabel("Remove attachment").accessibilityIdentifier("qa-overlay.attachment.remove.\(attachment.id)")
                  }
                }
              }
            }
          }
        }.padding(24).disabled(linear.locked)
      }.scrollDismissesKeyboard(.never)

      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 8) {
          if linear.pending && !linear.busy { Button("Edit report") { linear.editPending() } }
          attachmentToolbar
        }.padding(.horizontal, 12).padding(.bottom, 12)
      }
      }
      }.overlay(alignment: .center) { if linear.busy { ProgressView(linear.progress).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
      .overlay(alignment: .top) {
        if let issue = linear.created {
          Label("Ticket \(issue.identifier) created", systemImage: "checkmark.circle.fill")
            .font(.callout).foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(12).allowsHitTesting(false)
            .accessibilityIdentifier("qa-overlay.success")
        }
      }
      .navigationTitle(linear.authenticated ? (linear.teams.first(where: { $0.id == linear.teamId })?.name ?? draft.team) : "QA reporter")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if linear.authenticated {
          ToolbarItem(placement: .principal) { HStack(spacing: 0) { teamMenu } }
        }
        ToolbarItem(placement: .cancellationAction) {
          QaCloseButton(enabled: !linear.busy && !draft.isImporting) {
            if draft.hasContent { closeConfirmation = true }
            else { dismiss() }
          }.frame(width: 40, height: 40)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(linear.pending ? "Check submission" : "Submit ticket", systemImage: "arrow.up") { Task { await linear.submit(draft) } }
            .labelStyle(.iconOnly).disabled(!linear.authenticated || linear.busy || draft.isImporting || (!linear.pending && (draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || linear.stateId.isEmpty)))
            .accessibilityIdentifier("qa-overlay.submit")
        }
      }
      .background(Color(uiColor: .systemBackground))
    }
    .accessibilityHidden(preview != nil)
    .task { await linear.open() }
    .task(id: linear.authenticated && !linear.locked) {
      if !linear.authenticated { initialFocusRequested = false }
      await Task.yield()
      guard !Task.isCancelled, linear.authenticated, !linear.locked, !initialFocusRequested else { return }
      focusedField = .title
      initialFocusRequested = true
    }
    .alert("Save this draft?", isPresented: $closeConfirmation) {
      Button("Discard", role: .destructive) { linear.discardDraft(draft); dismiss() }
        .disabled(!linear.canDiscardDraft || draft.isImporting).accessibilityIdentifier("qa-overlay.discard")
      Button("Save draft", role: .cancel) { dismiss() }
        .disabled(linear.busy || draft.isImporting).accessibilityIdentifier("qa-overlay.save-draft")
    }
    .task(id: linear.created?.id) {
      guard let issue = linear.created else { return }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      UIAccessibility.post(notification: .announcement, argument: "Ticket \(issue.identifier) created")
      do { try await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 8 : 4)) }
      catch { return }
      if linear.created?.id == issue.id { linear.created = nil }
    }
    .onDisappear { linear.created = nil }
    .sheet(isPresented: $gallery, onDismiss: restoreEditorFocus) { QaGallery(draft: draft) }
    .sheet(item: $camera, onDismiss: restoreEditorFocus) { mode in QaCamera(draft: draft, mode: mode) }
    .fullScreenCover(item: $preview, onDismiss: restoreEditorFocus) { attachment in
      if #available(iOS 18.0, *), !reduceMotion {
        previewContent(attachment).navigationTransition(.zoom(sourceID: attachment.id, in: previewTransition))
      } else { previewContent(attachment) }
    }
    .alert("Report unavailable", isPresented: Binding(get: { draft.error != nil || linear.error != nil }, set: { if !$0 { draft.error = nil; linear.error = nil } })) {
      Button("OK") { draft.error = nil; linear.error = nil }
    } message: { Text(linear.error ?? draft.error ?? "") }
  }

  private func previewContent(_ attachment: QaAttachment) -> some View {
    QaAttachmentGallery(draft: draft, initial: attachment.id) { preview = nil }
  }

  private var teamMenu: some View {
    let selected = linear.teams.first(where: { $0.id == linear.teamId })
    let teams = linear.teams.map { team in
      UIAction(title: team.name, image: QaLinearIcons.image(team.icon, color: team.color), state: team.id == linear.teamId ? .on : .off) { _ in
        Task { await linear.selectTeam(team.id) }
      }
    }
    let account = UIAction(title: linear.viewer, attributes: .disabled) { _ in }
    let signOut = UIAction(title: "Sign out on this device", attributes: .destructive) { _ in Task { await linear.signOut() } }
    return QaLinearMenuButton(title: selected?.name ?? "Team", image: QaLinearIcons.image(selected?.icon, color: selected?.color),
      label: selected?.name ?? "Team", value: nil, identifier: "qa-overlay.team", enabled: !linear.locked,
      fontSize: teamFontSize, menu: UIMenu(children: [UIMenu(options: .displayInline, children: teams), account, signOut]))
      .fixedSize(horizontal: true, vertical: false).frame(height: 40).padding(.horizontal, 12)
      .modifier(QaGlassCapsule(interactive: true))
  }

  private var attachmentToolbar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 0) {
      QaLinearMenuButton(title: linear.states.first(where: { $0.id == linear.stateId })?.name ?? "Choose status",
        image: QaLinearIcons.image(linear.states.first(where: { $0.id == linear.stateId })?.icon, color: linear.states.first(where: { $0.id == linear.stateId })?.color, fallback: "IssueStatusTodo", size: toolbarIconSize),
        label: "Status", value: linear.states.first(where: { $0.id == linear.stateId })?.name ?? "Choose status",
        identifier: "qa-overlay.status", enabled: !linear.locked, fontSize: teamFontSize,
        menu: UIMenu(children: linear.states.map { state in
          UIAction(title: state.name, image: QaLinearIcons.image(state.icon, color: state.color), state: state.id == linear.stateId ? .on : .off) { _ in linear.stateId = state.id }
        }))
        .fixedSize(horizontal: true, vertical: false).frame(height: 44).padding(.horizontal, 8)
      Divider().frame(height: 24).padding(.horizontal, 8)
      tool("Gallery", "photo.on.rectangle") { fieldBeforePresentation = focusedField; gallery = true }
      tool("Take photo", "camera") { openCamera(.photo) }
      tool("Camera video", "video") { openCamera(.video) }
      tool("Record screen", "record.circle") { host.startRecording() }
    }
    .padding(.horizontal, 8)
    }
    .frame(height: 44)
    .scrollDismissesKeyboard(.never)
    .accessibilityIdentifier("qa-overlay.toolbar")
    .foregroundStyle(.primary).tint(.primary)
    .modifier(QaGlassCapsule(interactive: false))
  }

  private func tool(_ name: String, _ icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon).symbolRenderingMode(.monochrome)
        .font(.system(size: toolbarIconSize, weight: .regular))
        .frame(width: 48, height: 44).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(name).disabled(draft.isImporting || linear.locked)
  }

  private func restoreEditorFocus() {
    if let fieldBeforePresentation { focusedField = fieldBeforePresentation }
    fieldBeforePresentation = nil
  }

  private func openCamera(_ mode: CameraMode) {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      draft.error = "The camera is unavailable. Use a real device to take photos or camera videos."
      return
    }
    fieldBeforePresentation = focusedField
    camera = mode
  }
}

private final class QaLinearIcons {
  private static let bundle: Bundle = {
    let owner = Bundle(for: QaLinearIcons.self)
    return owner.url(forResource: "QaLinearIcons", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? owner
  }()
  static func image(_ name: String?, color: String? = nil, fallback: String = "Team", size: CGFloat = 16) -> UIImage {
    let image = name.flatMap { UIImage(named: "qa.linear." + $0, in: bundle, compatibleWith: nil) }
      ?? UIImage(named: "qa.linear." + fallback, in: bundle, compatibleWith: nil)
      ?? UIImage(systemName: "square.dashed")!
    let tinted = image.withTintColor(tint(color), renderingMode: .alwaysOriginal)
    return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
      tinted.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
    }.withRenderingMode(.alwaysOriginal)
  }
  private static func tint(_ hex: String?) -> UIColor {
    guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return .label }
    return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
  }
}

// UIKit keeps the same original-color image in the button and its native menu.
private struct QaLinearMenuButton: UIViewRepresentable {
  let title: String?
  let image: UIImage
  let label: String
  let value: String?
  let identifier: String
  let enabled: Bool
  let fontSize: CGFloat
  let menu: UIMenu
  func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .system)
    button.showsMenuAsPrimaryAction = true
    return button
  }
  func updateUIView(_ button: UIButton, context: Context) {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.image = image
    configuration.imagePadding = 8
    configuration.contentInsets = .zero
    configuration.baseForegroundColor = .label
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
      return attributes
    }
    button.configuration = configuration
    button.menu = menu
    button.isEnabled = enabled
    button.accessibilityLabel = label
    button.accessibilityValue = value
    button.accessibilityIdentifier = identifier
  }
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: proposal.height ?? 40)
  }
}

private struct QaCloseButton: UIViewRepresentable {
  let enabled: Bool
  let action: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UIButton {
    // The navigation toolbar supplies its native glass background.
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
    configuration.baseForegroundColor = .label
    let button = UIButton(configuration: configuration)
    button.accessibilityLabel = "Close reporter"
    button.accessibilityIdentifier = "qa-overlay.close"
    button.addAction(UIAction { [weak coordinator = context.coordinator] _ in
      coordinator?.parent.action()
    }, for: .touchUpInside)
    return button
  }
  func updateUIView(_ button: UIButton, context: Context) {
    context.coordinator.parent = self
    button.isEnabled = enabled
  }
  final class Coordinator {
    var parent: QaCloseButton
    init(_ parent: QaCloseButton) { self.parent = parent }
  }
}

private struct QaGlassCapsule: ViewModifier {
  let interactive: Bool
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular.interactive(interactive), in: .capsule)
    } else {
      content.background(.bar, in: Capsule())
    }
  }
}

private struct QaPreviewSource: ViewModifier {
  let id: UUID
  let namespace: Namespace.ID
  let reduceMotion: Bool
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 18.0, *), !reduceMotion { content.matchedTransitionSource(id: id, in: namespace) }
    else { content }
  }
}

enum CameraMode: String, Identifiable { case photo, video; var id: String { rawValue } }

struct QaGallery: UIViewControllerRepresentable {
  let draft: QaDraft
  @Environment(\.dismiss) private var dismiss
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration()
    configuration.filter = .any(of: [.images, .videos])
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = context.coordinator
    return picker
  }
  func updateUIViewController(_ controller: PHPickerViewController, context: Context) { }
  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let parent: QaGallery
    init(_ parent: QaGallery) { self.parent = parent }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      parent.dismiss()
      guard let provider = results.first?.itemProvider else { return }
      let video = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
      parent.draft.isImporting = true
      provider.loadFileRepresentation(forTypeIdentifier: video ? UTType.movie.identifier : UTType.image.identifier) { url, error in
        do {
          guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
          let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          guard bytes <= QaDraft.maxBytes else { throw NSError(domain: "QAOverlay", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a file smaller than 100 MB."]) }
          let target = try QaDraft.newFile(extension: url.pathExtension)
          try FileManager.default.copyItem(at: url, to: target)
          Task { @MainActor in self.parent.draft.addOwnedFile(target, video: video); self.parent.draft.isImporting = false }
        } catch {
          Task { @MainActor in self.parent.draft.error = error.localizedDescription; self.parent.draft.isImporting = false }
        }
      }
    }
  }
}

struct QaCamera: UIViewControllerRepresentable {
  let draft: QaDraft
  let mode: CameraMode
  @Environment(\.dismiss) private var dismiss
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.mediaTypes = [mode == .photo ? UTType.image.identifier : UTType.movie.identifier]
    picker.videoMaximumDuration = 60
    picker.delegate = context.coordinator
    return picker
  }
  func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: QaCamera
    init(_ parent: QaCamera) { self.parent = parent }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      parent.dismiss()
      do {
        let video = parent.mode == .video
        let target = try QaDraft.newFile(extension: video ? "mov" : "jpg")
        if video, let source = info[.mediaURL] as? URL {
          try FileManager.default.copyItem(at: source, to: target)
        } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
          try data.write(to: target, options: .atomic)
        } else { throw CocoaError(.fileReadUnknown) }
        parent.draft.addOwnedFile(target, video: video)
      } catch { parent.draft.error = error.localizedDescription }
    }
  }
}
