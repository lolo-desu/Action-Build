import Foundation

@main
enum CoreTests {
    static func main() throws {
        let values = try JSONDecoder().decode(JSON.self, from: Data("{\"items\":[{\"user\":{\"id\":\"person-1\",\"displayName\":\"访客\"}}],\"nextCursor\":null}".utf8))
        precondition(values.items.count == 1 && values.items[0].id == "person-1")
        precondition(values.items[0].name == "访客")
        let initial = [Item(.object(["id": .string("m1"), "text": .string("hello"), "createdAt": .string("2026-10-02T12:00:00Z")]))]
        let recalled = Item(.object(["id": .string("m1"), "recalled": .bool(true), "createdAt": .string("2026-10-02T12:00:00Z")]))
        let newer = Item(.object(["id": .string("m2"), "createdAt": .string("2026-10-02T12:01:00Z")]))
        let result = mergeMessages(initial, [newer, recalled, newer])
        precondition(result.count == 2 && result[0]["recalled"].bool && result[1].id == "m2")
        let text = JSON.object(["text": .string("引号\" 换行\n<标签> & 表情🙂"), "optional": .null])
        let decoded = try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(text))
        precondition(decoded == text)
        precondition(JSON.string("2026-10-02T12:00:00.123Z").date != nil)
        precondition(JSON.string("2026-10-02T12:00:00Z").date != nil)
        print("PASS: wrapped-user identity, response decoding, message merge/recall/deduplication, text encoding, dates")
    }
}
