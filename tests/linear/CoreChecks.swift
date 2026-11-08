import Foundation

final class MemoryTokens: QaLinearTokenStore, @unchecked Sendable {
  private let lock = NSLock()
  private var tokens: QaLinearTokens?
  init(_ tokens: QaLinearTokens?) { self.tokens = tokens }
  func load() -> QaLinearTokens? { lock.lock(); defer { lock.unlock() }; return tokens }
  func save(_ tokens: QaLinearTokens) { lock.lock(); defer { lock.unlock() }; self.tokens = tokens }
  func clear() { lock.lock(); defer { lock.unlock() }; tokens = nil }
}
final class MockLinear: URLProtocol, @unchecked Sendable {
  static var handler: (URLRequest) throws -> (Int, String) = { _ in fatalError("Missing handler") }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, body) = try Self.handler(request)
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
@main struct Checks {
  static func main() async throws {
    let redirect = "dev.example.qa://linear/callback"
    assert(QaLinearClient.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let nonce = try QaLinearClient.randomToken(); assert(nonce.count == 43)
    assert(QaLinearClient.validCallback(URL(string: redirect + "?code=a%2Bb&state=s")!, redirect: redirect, state: "s") == "a+b")
    for callback in [redirect + "?code=a&state=wrong", redirect + "?code=a&code=b&state=s", redirect + "?code=a&state=s&state=s", redirect + "?code=a&state=s#error", redirect + "?code=a&state=s&error=denied", "dev.example.qa://evil/callback?code=a&state=s", "dev.example.qa://user@linear/callback?code=a&state=s"] {
      assert(QaLinearClient.validCallback(URL(string: callback)!, redirect: redirect, state: "s") == nil)
    }
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockLinear.self]
    let session = URLSession(configuration: configuration)
    let store = MemoryTokens(QaLinearTokens(access: "old", refresh: "rotating", expires: .distantPast))
    let api = QaLinearClient(config: QaLinearConfig(clientId: "public-id", redirectUri: redirect, teamId: nil), store: store, session: session)
    var refreshes = 0
    MockLinear.handler = { request in
      if request.url!.path == "/oauth/token" {
        refreshes += 1
        assert(request.value(forHTTPHeaderField: "Authorization") == nil)
        return (200, #"{"access_token":"new","refresh_token":"replacement","expires_in":86400}"#)
      }
      assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer new")
      return (200, ##"{"data":{"viewer":{"name":"Tester","organization":{"name":"Workspace"}},"teams":{"nodes":[{"id":"team","name":"Product","key":"PRD","icon":"Bug","color":"#5e6ad2"}],"pageInfo":{"hasNextPage":false}}}}"##)
    }
    async let first = api.teams(); async let second = api.teams()
    let values = try await [first, second]
    assert(values.allSatisfy { $0.1.first?.id == "team" && $0.1.first?.icon == "Bug" && $0.1.first?.color == "#5e6ad2" }); assert(refreshes == 1); assert(store.load()?.refresh == "replacement")
    MockLinear.handler = { _ in (200, ##"{"data":{"team":{"states":{"nodes":[{"id":"state","name":"Done","type":"completed","color":"#00aa55"}],"pageInfo":{"hasNextPage":false}}}}}"##) }
    let states = try await api.states(teamId: "team")
    assert(states.first?.color == "#00aa55" && states.first?.icon == "IssueStatusDone")
    let expectedIcons = ["triage": "IssueStatusTriage", "backlog": "IssueStatusBacklog", "unstarted": "IssueStatusTodo", "started": "IssueStatusStarted", "completed": "IssueStatusDone", "canceled": "StatusCanceled", "duplicate": "StatusDuplicate", "unknown": "IssueStatusTodo"]
    for (type, icon) in expectedIcons { assert(QaLinearState(id: "state", name: "Status", type: type).icon == icon) }
    MockLinear.handler = { _ in (200, #"{"errors":[{"message":"Denied"}],"data":{"issueCreate":{"success":true}}}"#) }
    do { _ = try await api.create(input: ["id": "same-id"]); fatalError("GraphQL errors must reject partial data") } catch is QaLinearError {}
    MockLinear.handler = { _ in (200, #"{"data":{"teams":{"nodes":[],"pageInfo":{"hasNextPage":true}}}}"#) }
    do { _ = try await api.teams(); fatalError("Missing cursor must reject pagination") } catch is QaLinearError {}
    MockLinear.handler = { _ in (429, "{}") }
    do { _ = try await api.teams(); fatalError("Rate limiting must reject") } catch is QaLinearError {}
    MockLinear.handler = { _ in (200, #"{"data":{"issues":{"nodes":[{"id":"same-id","identifier":"PRD-1","url":"https://linear.app/team/issue/PRD-1"}]}}}"#) }
    let recovered = try await api.findIssue(id: "same-id"); assert(recovered?.id == "same-id")
    MockLinear.handler = { _ in (200, #"{"data":{"issues":{"nodes":[{"id":"x","identifier":"X-1","url":"https://evil.example/ticket"}]}}}"#) }
    do { _ = try await api.findIssue(id: "x"); fatalError("Untrusted receipt must reject") } catch is QaLinearError {}
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1, 2]).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
    MockLinear.handler = { _ in (200, #"{"data":{"fileUpload":{"success":true,"uploadFile":{"uploadUrl":"http://evil.example/upload","assetUrl":"https://uploads.linear.app/a","headers":[]}}}}"#) }
    do { _ = try await api.upload(file: file, mime: "image/jpeg"); fatalError("Insecure upload must reject") } catch is QaLinearError {}
    MockLinear.handler = { request in
      if request.url!.host == "storage.example" {
        assert(request.httpMethod == "PUT")
        assert(request.value(forHTTPHeaderField: "Authorization") == nil)
        assert(request.value(forHTTPHeaderField: "x-upload-test") == "signed-value")
        assert(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        return (201, "")
      }
      return (200, #"{"data":{"fileUpload":{"success":true,"uploadFile":{"uploadUrl":"https://storage.example/file","assetUrl":"https://uploads.linear.app/private-file","headers":[{"key":"x-upload-test","value":"signed-value"}]}}}}"#)
    }
    let uploaded = try await api.upload(file: file, mime: "image/jpeg")
    assert(uploaded == "https://uploads.linear.app/private-file")
    var requests = 0
    MockLinear.handler = { request in
      if request.url!.path == "/oauth/token" { return (200, #"{"access_token":"refreshed","refresh_token":"rotated-again","expires_in":86400}"#) }
      requests += 1
      if requests == 1 { return (401, "{}") }
      assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed")
      return (200, #"{"data":{"issueCreate":{"success":true,"issue":{"id":"same-id","identifier":"PRD-1","url":"https://linear.app/team/issue/PRD-1"}}}}"#)
    }
    let created = try await api.create(input: ["id": "same-id", "title": "Bug"])
    assert(created.id == "same-id" && requests == 2)
    requests = 0
    MockLinear.handler = { request in
      if request.url!.path == "/oauth/token" { return (200, #"{"access_token":"graphql-refreshed","refresh_token":"new-pair","expires_in":86400}"#) }
      requests += 1
      if requests == 1 { return (200, #"{"errors":[{"extensions":{"code":"UNAUTHENTICATED"}}]}"#) }
      assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer graphql-refreshed")
      return (200, #"{"data":{"issues":{"nodes":[]}}}"#)
    }
    let absent = try await api.findIssue(id: "same-id"); assert(absent == nil && requests == 2)
    store.save(QaLinearTokens(access: "expired", refresh: "revoked", expires: .distantPast))
    MockLinear.handler = { _ in (400, "{}") }
    do { _ = try await api.teams(); fatalError("Revoked refresh must reject") } catch QaLinearError.unauthorized {}
    assert(store.load() == nil)
    print("Linear native core: PKCE, callback validation, rotating single-flight refresh, GraphQL errors, pagination, rate limits, recovery and URL validation passed")
  }
}
