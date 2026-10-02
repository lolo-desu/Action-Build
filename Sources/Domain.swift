import Foundation

enum JSON: Codable, Hashable, Sendable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSON].self) { self = .object(v) }
        else { self = .array(try c.decode([JSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSON { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    var string: String { if case .string(let s) = self { return s }; if case .number(let n) = self { return String(Int(n)) }; return "" }
    var int: Int { if case .number(let n) = self { return Int(n) }; return 0 }
    var bool: Bool { if case .bool(let b) = self { return b }; return false }
    var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    var present: Bool { self != .null }
    var items: [Item] { (self["items"].present ? self["items"].array : array).map(Item.init).filter { !$0.id.isEmpty } }
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

struct Item: Identifiable, Hashable, Sendable {
    var value: JSON
    init(_ value: JSON) { self.value = value }
    var id: String { value["id"].string.isEmpty ? value["user"]["id"].string : value["id"].string }
    subscript(_ key: String) -> JSON { value[key] }
    var user: JSON { value["user"].present ? value["user"] : value["author"].present ? value["author"] : value }
    var name: String { user["displayName"].string.isEmpty ? "用户" : user["displayName"].string }
    var avatar: JSON { user["avatar"].present ? user["avatar"] : user["cover"] }
}

enum ContentMode: String, CaseIterable, Identifiable {
    case sfw, mixed, nsfw
    var id: String { rawValue }
    var title: String { switch self { case .sfw: "普通"; case .mixed: "全部"; case .nsfw: "成人" } }
}

struct ServiceError: LocalizedError {
    let status: Int
    let code: String
    let message: String
    var errorDescription: String? { message.isEmpty ? "请求失败（\(status)，\(code)）" : message }
}

func mergeMessages(_ old: [Item], _ new: [Item]) -> [Item] {
    var values = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    for item in new { values[item.id] = item }
    return values.values.sorted {
        let a = $0["createdAt"].string, b = $1["createdAt"].string
        return a == b ? $0.id < $1.id : a < b
    }
}
