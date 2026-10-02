import Foundation
import Observation
import UserNotifications
import UIKit

@MainActor @Observable
final class AppStore {
    enum Phase: Equatable { case loading, loggedOut, ready, failed }
    let client = Client()
    var phase = Phase.loading
    var me = JSON.null
    var error = ""
    var counters = JSON.null
    var eventVersion = 0
    var activeMatchID: String?
    var mode: ContentMode = ContentMode(rawValue: UserDefaults.standard.string(forKey: "NativeContentMode") ?? "sfw") ?? .sfw {
        didSet { client.mode = mode; UserDefaults.standard.set(mode.rawValue, forKey: "NativeContentMode"); eventVersion += 1 }
    }
    var demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo")
    private var socket: URLSessionWebSocketTask?
    private var socketLoop: Task<Void, Never>?
    private var foreground = true
    init() { client.mode = mode }
    func bootstrap(showLoading: Bool = true) async {
        if demo { me = Demo.me; phase = .ready; return }
        let previousPhase = phase
        if showLoading { phase = .loading }
        await client.importWebCookies()
        do {
            me = try await client.request("/me")
            phase = .ready
            counters = (try? await client.request("/me/counters")) ?? .null
            connect()
        } catch let e as ServiceError where e.status == 401 {
            me = .null; phase = .loggedOut; disconnect()
        } catch {
            self.error = error.localizedDescription
            phase = !showLoading && previousPhase == .ready ? .ready : .failed
        }
    }
    func get(_ path: String, query: [String: String] = [:]) async throws -> JSON {
        if demo { return Demo.response(path) }
        return try await client.request(path, query: query)
    }
    func mutate(_ path: String, method: String = "POST", body: JSON? = nil) async throws -> JSON {
        if demo { throw ServiceError(status: 0, code: "DEMO", message: "界面预览不发送任何操作。") }
        let result = try await client.request(path, method: method, body: body)
        eventVersion += 1
        return result
    }
    func logout() async throws {
        _ = try await mutate("/auth/logout")
        disconnect(); me = .null; counters = .null; phase = .loggedOut
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    func lifecycle(active: Bool) {
        foreground = active
        if active { connect() } else { disconnect() }
    }
    func connect() {
        guard !demo, foreground, phase == .ready, socketLoop == nil else { return }
        socketLoop = Task { [weak self] in
            var delay = 1
            while let self, !Task.isCancelled, self.foreground, self.phase == .ready {
                do {
                    var req = URLRequest(url: URL(string: "wss://erp.sex/api/v1/ws")!)
                    req.setValue(Client.origin.absoluteString, forHTTPHeaderField: "Origin")
                    let cookies = HTTPCookieStorage.shared.cookies(for: Client.origin) ?? []
                    for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) { req.setValue(value, forHTTPHeaderField: key) }
                    let task = self.client.session.webSocketTask(with: req)
                    self.socket = task; task.resume()
                    try await task.send(.string("{\"type\":\"visibility\",\"data\":{\"visible\":true}}"))
                    self.eventVersion += 1
                    while !Task.isCancelled {
                        let event = try await task.receive()
                        let data: Data
                        switch event { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                        let json = try JSONDecoder().decode(JSON.self, from: data)
                        delay = 1
                        if json["type"].string == "ping" { try await task.send(.string("{\"type\":\"pong\"}")); continue }
                        self.handle(json)
                    }
                } catch {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .seconds(delay)); delay = min(30, delay * 2)
                }
            }
        }
    }
    func disconnect() { socketLoop?.cancel(); socketLoop = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil }
    private func handle(_ event: JSON) {
        let type = event["type"].string, data = event["data"]
        if type == "counters" {
            counters = data
            UIApplication.shared.applicationIconBadgeNumber = data["unreadMessages"].int + data["unreadNotifications"].int
        }
        if ["message.new", "message.recalled", "match.new", "match.closed", "match.updated", "notification.new", "account.updated"].contains(type) { eventVersion += 1 }
        if UserDefaults.standard.bool(forKey: "NativeLocalAlerts"), type == "message.new", data["senderId"].string != me["id"].string, data["matchId"].string != activeMatchID {
            let content = UNMutableNotificationContent()
            content.title = "vrcrp"; content.body = "你有新的聊天消息"; content.sound = .default
            content.userInfo = ["matchID": data["matchId"].string]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "chat-" + data["matchId"].string, content: content, trigger: nil))
        }
    }
}

enum Demo {
    static func json(_ text: String) -> JSON { try! JSONDecoder().decode(JSON.self, from: Data(text.utf8)) }
    static let me = json("""
    {"id":"demo-me","displayName":"旅行者","status":"active","settings":{"notify":{}},"energy":{"balance":65}}
    """)
    static let people = json("""
    {"items":[{"id":"demo-1","displayName":"林间","tagline":"一起探索新的世界","languages":["zh"],"intents":["friendship"],"relation":{"swiped":"none"}},{"id":"demo-2","displayName":"远星","tagline":"喜欢摄影和安静的聊天","languages":["zh","en"],"intents":["friendship"],"relation":{"swiped":"none"}}]}
    """)
    static let matches = json("""
    {"items":[{"id":"demo-match","state":"active","user":{"id":"demo-1","displayName":"林间"},"unreadCount":2,"lastMessage":{"type":"text","text":"今天一起看看新地图吗？","createdAt":"2026-10-02T12:01:00Z"}}]}
    """)
    static let messages = json("""
    {"items":[{"id":"m1","senderId":"demo-1","type":"text","text":"今天一起看看新地图吗？","createdAt":"2026-10-02T12:00:00Z"},{"id":"m2","senderId":"demo-me","type":"text","text":"好呀，晚点见。","createdAt":"2026-10-02T12:01:00Z"}],"hasMore":false}
    """)
    static func response(_ path: String) -> JSON {
        if path.contains("/messages") { return messages }
        if path == "/matches" { return matches }
        if path.hasPrefix("/matches/") { return json("{\"id\":\"demo-match\",\"state\":\"active\",\"user\":{\"id\":\"demo-1\",\"displayName\":\"林间\"},\"boundary\":{\"required\":false}}") }
        if path == "/me/profile" { return me }
        if path.hasPrefix("/profiles/") { return people["items"].array.first! }
        if path == "/feed" || path == "/browse" || path.hasPrefix("/likes") { return people }
        return json("{\"items\":[]}")
    }
}
