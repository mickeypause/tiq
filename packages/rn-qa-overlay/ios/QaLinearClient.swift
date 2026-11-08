import CryptoKit
import Foundation
import Security

struct QaLinearConfig: Sendable {
  let clientId: String
  let redirectUri: String
  let teamId: String?
  var storageKey: String { SHA256.hash(data: Data((clientId + redirectUri).utf8)).map { String(format: "%02x", $0) }.joined() }
}
struct QaLinearTeam: Identifiable, Sendable { let id: String; let name: String; let key: String; var icon: String? = nil; var color: String? = nil }
struct QaLinearState: Identifiable, Sendable {
  let id: String; let name: String; let type: String
  var color: String? = nil
  var icon: String {
    switch type {
    case "triage": return "IssueStatusTriage"
    case "backlog": return "IssueStatusBacklog"
    case "unstarted": return "IssueStatusTodo"
    case "started": return "IssueStatusStarted"
    case "completed": return "IssueStatusDone"
    case "canceled": return "StatusCanceled"
    case "duplicate": return "StatusDuplicate"
    default: return "IssueStatusTodo"
    }
  }
}
struct QaLinearIssue: Identifiable, Sendable { let id: String; let identifier: String; let url: URL }
struct QaLinearTokens: Codable, Sendable { let access: String; let refresh: String; let expires: Date }
enum QaLinearError: LocalizedError {
  case unauthorized, message(String)
  var errorDescription: String? {
    switch self {
    case .unauthorized: return "Your Linear session expired. Please sign in again."
    case .message(let message): return message
    }
  }
}

protocol QaLinearTokenStore: Sendable {
  func load() throws -> QaLinearTokens?
  func save(_ tokens: QaLinearTokens) throws
  func clear() throws
}
struct QaLinearKeychain: QaLinearTokenStore {
  let key: String
  private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "rn-qa-overlay.linear", kSecAttrAccount as String: key] }
  func load() throws -> QaLinearTokens? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw QaLinearError.message("Could not read secure Linear credentials.") }
    return try JSONDecoder().decode(QaLinearTokens.self, from: data)
  }
  func save(_ tokens: QaLinearTokens) throws {
    let data = try JSONEncoder().encode(tokens)
    var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var request = query
      request[kSecValueData as String] = data
      request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(request as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw QaLinearError.message("Could not save secure Linear credentials.") }
  }
  func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw QaLinearError.message("Could not remove secure Linear credentials.") }
  }
}

final class QaLinearNoRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

actor QaLinearClient {
  let config: QaLinearConfig
  private let store: any QaLinearTokenStore
  private let session: URLSession
  private var refreshTask: Task<QaLinearTokens, Error>?
  init(config: QaLinearConfig, store: (any QaLinearTokenStore)? = nil, session: URLSession? = nil) {
    self.config = config
    self.store = store ?? QaLinearKeychain(key: config.storageKey)
    if let session { self.session = session }
    else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpShouldSetCookies = false
      configuration.timeoutIntervalForRequest = 60
      self.session = URLSession(configuration: configuration, delegate: QaLinearNoRedirects(), delegateQueue: nil)
    }
  }
  func hasCredentials() throws -> Bool { try store.load() != nil }
  func clear() throws { try store.clear() }
  func authorize(code: String, verifier: String) async throws {
    try store.save(try await tokenRequest(["grant_type": "authorization_code", "client_id": config.clientId, "redirect_uri": config.redirectUri, "code": code, "code_verifier": verifier]))
  }
  private func tokenRequest(_ fields: [String: String]) async throws -> QaLinearTokens {
    var request = URLRequest(url: URL(string: "https://api.linear.app/oauth/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(Self.form(fields).utf8)
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 400 || status == 401 { throw QaLinearError.unauthorized }
    guard (200..<300).contains(status), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let access = object["access_token"] as? String, !access.isEmpty,
      let refresh = object["refresh_token"] as? String, !refresh.isEmpty,
      let seconds = object["expires_in"] as? Double, seconds > 0 else { throw QaLinearError.message("Linear sign-in could not be completed. Try again.") }
    return QaLinearTokens(access: access, refresh: refresh, expires: Date().addingTimeInterval(seconds))
  }
  private func accessToken(force: Bool = false) async throws -> String {
    guard let tokens = try store.load() else { throw QaLinearError.unauthorized }
    if !force && tokens.expires.timeIntervalSinceNow > 60 { return tokens.access }
    if let refreshTask { return try await refreshTask.value.access }
    let task = Task { try await self.tokenRequest(["grant_type": "refresh_token", "client_id": self.config.clientId, "refresh_token": tokens.refresh]) }
    refreshTask = task
    do {
      let replacement = try await task.value
      try store.save(replacement)
      refreshTask = nil
      return replacement.access
    } catch {
      refreshTask = nil
      if case QaLinearError.unauthorized = error { try store.clear() }
      throw error
    }
  }
  private func query(_ query: String, _ variables: [String: Any] = [:], retryAuth: Bool = true) async throws -> [String: Any] {
    var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 401, retryAuth {
      _ = try await accessToken(force: true)
      return try await self.query(query, variables, retryAuth: false)
    }
    if status == 401 { throw QaLinearError.unauthorized }
    if status == 429 { throw QaLinearError.message("Linear's rate limit was reached. Try again later.") }
    guard (200..<300).contains(status) else { throw QaLinearError.message("Linear request failed (HTTP \(status)). Your draft is safe.") }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QaLinearError.message("Linear returned an invalid response.") }
    if let errors = object["errors"] as? [[String: Any]], !errors.isEmpty {
      if errors.contains(where: { ((($0["extensions"] as? [String: Any])?["code"] as? String) ?? "").contains("AUTHENTICAT") }) {
        if retryAuth {
          _ = try await accessToken(force: true)
          return try await self.query(query, variables, retryAuth: false)
        }
        throw QaLinearError.unauthorized
      }
      throw QaLinearError.message("Linear could not complete the request. Check your workspace permissions and try again.")
    }
    guard let result = object["data"] as? [String: Any] else { throw QaLinearError.message("Linear returned no data.") }
    return result
  }
  func teams() async throws -> (String, [QaLinearTeam]) {
    var teams: [QaLinearTeam] = []
    var cursor: String?
    var viewer = ""
    repeat {
      let data = try await query("query Teams($after:String){viewer{name organization{name}} teams(first:100,after:$after){nodes{id name key icon color} pageInfo{hasNextPage endCursor}}}", ["after": cursor as Any? ?? NSNull()])
      if let user = data["viewer"] as? [String: Any] { viewer = (user["name"] as? String ?? "") + " · " + ((user["organization"] as? [String: Any])?["name"] as? String ?? "") }
      guard let connection = data["teams"] as? [String: Any], let nodes = connection["nodes"] as? [[String: Any]] else { throw QaLinearError.message("Could not load Linear teams.") }
      for node in nodes {
        guard let id = node["id"] as? String, let name = node["name"] as? String, let key = node["key"] as? String else { throw QaLinearError.message("Linear returned an invalid team.") }
        teams.append(QaLinearTeam(id: id, name: name, key: key, icon: node["icon"] as? String, color: node["color"] as? String))
      }
      let page = connection["pageInfo"] as? [String: Any]
      let next = page?["hasNextPage"] as? Bool == true ? page?["endCursor"] as? String : nil
      guard page?["hasNextPage"] as? Bool != true || (next != nil && next != cursor) else { throw QaLinearError.message("Linear team pagination did not advance.") }
      cursor = next
    } while cursor != nil
    return (viewer, teams)
  }
  func states(teamId: String) async throws -> [QaLinearState] {
    var states: [QaLinearState] = []
    var cursor: String?
    repeat {
      let data = try await query("query States($team:String!,$after:String){team(id:$team){states(first:100,after:$after){nodes{id name type color} pageInfo{hasNextPage endCursor}}}}", ["team": teamId, "after": cursor as Any? ?? NSNull()])
      guard let team = data["team"] as? [String: Any], let connection = team["states"] as? [String: Any], let nodes = connection["nodes"] as? [[String: Any]] else { throw QaLinearError.message("Could not load the team's workflow states.") }
      for node in nodes {
        guard let id = node["id"] as? String, let name = node["name"] as? String, let type = node["type"] as? String else { throw QaLinearError.message("Linear returned an invalid workflow state.") }
        states.append(QaLinearState(id: id, name: name, type: type, color: node["color"] as? String))
      }
      let page = connection["pageInfo"] as? [String: Any]
      let next = page?["hasNextPage"] as? Bool == true ? page?["endCursor"] as? String : nil
      guard page?["hasNextPage"] as? Bool != true || (next != nil && next != cursor) else { throw QaLinearError.message("Linear state pagination did not advance.") }
      cursor = next
    } while cursor != nil
    return states
  }
  func upload(file: URL, mime: String) async throws -> String {
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size > 0, size <= 100 * 1024 * 1024 else { throw QaLinearError.message("Attachments must be non-empty and smaller than 100 MB.") }
    let data = try await query("mutation Upload($type:String!,$name:String!,$size:Int!){fileUpload(contentType:$type,filename:$name,size:$size){success uploadFile{uploadUrl assetUrl headers{key value}}}}", ["type": mime, "name": file.lastPathComponent, "size": size])
    guard let payload = data["fileUpload"] as? [String: Any], payload["success"] as? Bool == true,
      let upload = payload["uploadFile"] as? [String: Any], let address = upload["uploadUrl"] as? String, let url = URL(string: address), url.scheme == "https", url.user == nil, url.password == nil,
      let asset = upload["assetUrl"] as? String, let assetURL = URL(string: asset), assetURL.scheme == "https", assetURL.host == "uploads.linear.app", assetURL.user == nil, assetURL.password == nil,
      let headers = upload["headers"] as? [[String: String]] else { throw QaLinearError.message("Linear did not provide a valid upload destination.") }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(mime, forHTTPHeaderField: "Content-Type")
    request.setValue("public, max-age=31536000", forHTTPHeaderField: "Cache-Control")
    for header in headers {
      guard let key = header["key"], let value = header["value"], !["authorization", "cookie", "proxy-authorization"].contains(key.lowercased()) else { throw QaLinearError.message("Linear returned unsupported upload headers.") }
      request.setValue(value, forHTTPHeaderField: key)
    }
    let (_, response) = try await session.upload(for: request, fromFile: file)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw QaLinearError.message("Attachment upload failed. Your draft is safe.") }
    return asset
  }
  func create(input: [String: Any]) async throws -> QaLinearIssue {
    let data = try await query("mutation Create($input:IssueCreateInput!){issueCreate(input:$input){success issue{id identifier url}}}", ["input": input])
    guard let payload = data["issueCreate"] as? [String: Any], payload["success"] as? Bool == true, let issue = payload["issue"] as? [String: Any] else { throw QaLinearError.message("Linear did not confirm ticket creation. Check submission status before trying again.") }
    return try Self.issue(issue)
  }
  func findIssue(id: String) async throws -> QaLinearIssue? {
    let data = try await query("query Find($id:ID!){issues(filter:{id:{eq:$id}},first:1){nodes{id identifier url}}}", ["id": id])
    guard let connection = data["issues"] as? [String: Any], let nodes = connection["nodes"] as? [[String: Any]] else { throw QaLinearError.message("Could not check ticket creation status.") }
    return try nodes.first.map(Self.issue)
  }
  private static func issue(_ data: [String: Any]) throws -> QaLinearIssue {
    guard let id = data["id"] as? String, let identifier = data["identifier"] as? String, let address = data["url"] as? String,
      let url = URL(string: address), url.scheme == "https", url.host == "linear.app", url.user == nil else { throw QaLinearError.message("Linear returned an invalid ticket receipt.") }
    return QaLinearIssue(id: id, identifier: identifier, url: url)
  }
  static func form(_ fields: [String: String]) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return fields.sorted(by: { $0.key < $1.key }).map { $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&")
  }
  static func randomToken() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw QaLinearError.message("Secure sign-in could not start.") }
    return base64url(Data(bytes))
  }
  static func base64url(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
  static func challenge(_ verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }
  static func validCallback(_ url: URL, redirect: String, state: String) -> String? {
    guard let expected = URL(string: redirect), url.scheme == expected.scheme, url.host == expected.host, url.path == expected.path, url.port == expected.port, url.fragment == nil, url.user == nil, url.password == nil,
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      items.filter({ $0.name == "state" }).count == 1, items.filter({ $0.name == "code" }).count == 1,
      items.first(where: { $0.name == "state" })?.value == state, !items.contains(where: { $0.name == "error" }),
      let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
    return code
  }
}
