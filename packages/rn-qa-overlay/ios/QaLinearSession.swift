import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class QaLinearSession: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
  static let shared = QaLinearSession()
  @Published var authenticated = false
  @Published var busy = false
  @Published var progress = ""
  @Published var viewer = ""
  @Published var teams: [QaLinearTeam] = []
  @Published var states: [QaLinearState] = []
  @Published var teamId = ""
  @Published var stateId = ""
  @Published var error: String?
  @Published var created: QaLinearIssue?
  @Published private(set) var pending = false
  private let config: QaLinearConfig?
  private let client: QaLinearClient?
  private var webSession: ASWebAuthenticationSession?
  private var attemptedLogin = false
  // shortcut: drafts and submission recovery live for this process; persist together before supporting process-restored drafts.
  private var submissionId: String?
  private var pendingInput: [String: Any]?
  private var uploaded: [UUID: String] = [:]
  var configured: Bool { config != nil }
  var locked: Bool { busy || pending }
  var canDiscardDraft: Bool { !busy && submissionId == nil }

  override init() {
    if let id = Bundle.main.object(forInfoDictionaryKey: "RnQaOverlayLinearClientId") as? String,
      let redirect = Bundle.main.object(forInfoDictionaryKey: "RnQaOverlayLinearRedirectUri") as? String, !id.isEmpty {
      let configuration = QaLinearConfig(clientId: id, redirectUri: redirect, teamId: Bundle.main.object(forInfoDictionaryKey: "RnQaOverlayLinearTeamId") as? String)
      config = configuration
      client = QaLinearClient(config: configuration)
    } else { config = nil; client = nil }
    super.init()
  }
  func open() async {
    guard let client, !busy, !authenticated else { return }
    do {
      if try await client.hasCredentials() {
        busy = true; progress = "Loading Linear…"
        defer { busy = false }
        try await loadWorkspace()
      } else if !attemptedLogin { await signIn() }
    } catch { await failure(error) }
  }
  func signIn() async {
    guard let config, let client, !busy else { return }
    attemptedLogin = true
    busy = true; progress = "Signing in to Linear…"
    defer { busy = false }
    do {
      let verifier = try QaLinearClient.randomToken()
      let state = try QaLinearClient.randomToken()
      var authorize = URLComponents(string: "https://linear.app/oauth/authorize")!
      authorize.queryItems = ["client_id": config.clientId, "redirect_uri": config.redirectUri, "response_type": "code", "scope": "read,write", "state": state, "code_challenge": QaLinearClient.challenge(verifier), "code_challenge_method": "S256"].map { URLQueryItem(name: $0.key, value: $0.value) }
      let callback: URL = try await withCheckedThrowingContinuation { continuation in
        let session = ASWebAuthenticationSession(url: authorize.url!, callbackURLScheme: URL(string: config.redirectUri)?.scheme) { [weak self] url, error in
          Task { @MainActor in
            self?.webSession = nil
            if let error { continuation.resume(throwing: error) }
            else if let url { continuation.resume(returning: url) }
            else { continuation.resume(throwing: QaLinearError.message("Linear sign-in returned no callback.")) }
          }
        }
        session.presentationContextProvider = self
        webSession = session
        if !session.start() { webSession = nil; continuation.resume(throwing: QaLinearError.message("Could not open Linear sign-in.")) }
      }
      guard let code = QaLinearClient.validCallback(callback, redirect: config.redirectUri, state: state) else { throw QaLinearError.message("Linear sign-in could not be verified. Please try again.") }
      try await client.authorize(code: code, verifier: verifier)
      try await loadWorkspace()
    } catch {
      if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { await failure(error) }
    }
  }
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
  }
  private func loadWorkspace() async throws {
    guard let client else { return }
    let (user, available) = try await client.teams()
    guard !available.isEmpty else { throw QaLinearError.message("This account has no accessible Linear teams.") }
    let selected: QaLinearTeam
    if let required = config?.teamId {
      guard let match = available.first(where: { $0.id.lowercased() == required.lowercased() }) else { throw QaLinearError.message("The configured Linear team is not accessible to this account.") }
      selected = match
    } else {
      let saved = UserDefaults.standard.string(forKey: "rn-qa-overlay.linear.team")
      selected = available.first(where: { $0.id == saved }) ?? available[0]
    }
    viewer = user; teams = available; teamId = selected.id
    try await loadStates()
    authenticated = true
  }
  private func loadStates() async throws {
    guard let client else { return }
    states = []
    stateId = ""
    let available = try await client.states(teamId: teamId)
    guard !available.isEmpty else { throw QaLinearError.message("This Linear team has no workflow states.") }
    states = available
    stateId = (available.first(where: { $0.type == "triage" }) ?? available.first(where: { $0.type == "backlog" }) ?? available[0]).id
    UserDefaults.standard.set(teamId, forKey: "rn-qa-overlay.linear.team")
  }
  func selectTeam(_ id: String) async {
    guard !locked, teams.contains(where: { $0.id == id }) else { return }
    teamId = id; busy = true; progress = "Loading workflow…"
    defer { busy = false }
    do { try await loadStates() } catch { await failure(error) }
  }
  func signOut() async {
    guard !locked, let client else { return }
    do {
      try await client.clear()
      authenticated = false; teams = []; states = []; viewer = ""; teamId = ""; stateId = ""; uploaded = [:]
    } catch { self.error = error.localizedDescription }
  }
  func submit(_ draft: QaDraft) async {
    guard let client, authenticated, !busy, !draft.isImporting else { return }
    guard pendingInput != nil || (!draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && states.contains(where: { $0.id == stateId })) else { return }
    busy = true; progress = pending ? "Checking submission…" : "Creating ticket…"
    defer { busy = false }
    do {
      if let id = submissionId, let issue = try await client.findIssue(id: id) { complete(issue, draft); return }
      if pendingInput == nil {
        var body = draft.description
        for (index, attachment) in draft.attachments.enumerated() {
          progress = "Uploading attachment \(index + 1) of \(draft.attachments.count)…"
          let asset: String
          if let saved = uploaded[attachment.id] { asset = saved }
          else {
            let mime = UTType(filenameExtension: attachment.url.pathExtension)?.preferredMIMEType ?? (attachment.isVideo ? "video/mp4" : "image/jpeg")
            asset = try await client.upload(file: attachment.url, mime: mime)
            uploaded[attachment.id] = asset
          }
          body += "\n\n![\(attachment.isVideo ? "Video" : "Image")](\(asset))"
        }
        if submissionId == nil { submissionId = UUID().uuidString.lowercased() }
        pendingInput = ["id": submissionId!, "title": draft.title.trimmingCharacters(in: .whitespacesAndNewlines), "description": body, "teamId": teamId, "stateId": stateId]
        pending = true
      }
      progress = "Creating ticket…"
      guard let input = pendingInput else { return }
      complete(try await client.create(input: input), draft)
    } catch { await failure(error) }
  }
  func discardDraft(_ draft: QaDraft) {
    guard canDiscardDraft else { return }
    uploaded = [:]
    stateId = (states.first(where: { $0.type == "triage" }) ?? states.first(where: { $0.type == "backlog" }) ?? states.first)?.id ?? ""
    draft.error = nil
    draft.discard()
  }
  func editPending() {
    guard !busy else { return }
    pendingInput = nil; pending = false
  }
  private func complete(_ issue: QaLinearIssue, _ draft: QaDraft) {
    created = issue; submissionId = nil; pendingInput = nil; pending = false; uploaded = [:]
    draft.discard()
  }
  private func failure(_ failure: Error) async {
    if case QaLinearError.unauthorized = failure {
      try? await client?.clear()
      authenticated = false; teams = []; states = []
    }
    error = failure.localizedDescription + (pending ? " Check submission before making another report." : "")
  }
}
