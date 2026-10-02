import Foundation
import WebKit

@MainActor
final class Client {
    static let origin = URL(string: "https://erp.sex")!
    var mode: ContentMode = .sfw
    let session: URLSession
    init() {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.timeoutIntervalForRequest = 30
        session = URLSession(configuration: c)
    }
    func importWebCookies() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain == "erp.sex" || cookie.domain == ".erp.sex" {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
    func exportWebCookies() async {
        for cookie in HTTPCookieStorage.shared.cookies(for: Self.origin) ?? [] {
            await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
        }
    }
    func request(_ path: String, method: String = "GET", body: JSON? = nil, query: [String: String] = [:]) async throws -> JSON {
        let req = try makeRequest(path, method: method, body: body, query: query)
        let (data, response) = try await session.data(for: req)
        let result = try parse(data, response)
        await exportWebCookies()
        return result
    }
    func makeRequest(_ path: String, method: String = "GET", body: JSON? = nil, query: [String: String] = [:]) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.hasPrefix("//") else { throw URLError(.badURL) }
        var components = URLComponents(url: Self.origin.appendingPathComponent("api/v1" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("zh-Hant", forHTTPHeaderField: "Accept-Language")
        req.setValue(mode.rawValue, forHTTPHeaderField: "X-Content-Mode")
        req.setValue(Self.origin.absoluteString, forHTTPHeaderField: "Origin")
        if method != "GET" && method != "HEAD", let csrf = (HTTPCookieStorage.shared.cookies(for: Self.origin) ?? []).first(where: { $0.name == "erp_csrf" }) {
            req.setValue(csrf.value.removingPercentEncoding ?? csrf.value, forHTTPHeaderField: "X-CSRF-Token")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        return req
    }
    func parse(_ data: Data, _ response: URLResponse) throws -> JSON {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? JSON.null : (try? JSONDecoder().decode(JSON.self, from: data)) ?? .null
        guard (200..<300).contains(status) else {
            throw ServiceError(status: status, code: json["error"]["code"].string, message: json["error"]["message"].string)
        }
        return json
    }
    func upload(_ data: Data, filename: String, mime: String, purpose: String, matchID: String, rating: String, realPerson: Bool, r18Kind: String = "", adultConfirmed: Bool = false) async throws -> JSON {
        let boundary = "vrcrp-" + UUID().uuidString
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        var fields = ["purpose": purpose, "matchId": matchID, "rating": rating, "realPerson": String(realPerson)]
        if rating == "r18" { fields["r18Kind"] = r18Kind; fields["adultConfirm"] = String(adultConfirmed) }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data); append("\r\n--\(boundary)--\r\n")
        var req = try makeRequest("/media", method: "POST")
        req.httpBody = body
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (result, response) = try await session.data(for: req)
        let json = try parse(result, response)
        await exportWebCookies()
        return json
    }
}
