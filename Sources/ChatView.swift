import SwiftUI
import PhotosUI
import AVKit

struct MatchesView: View {
    @Environment(AppStore.self) private var store
    @State private var state = "active"
    @State private var items: [Item] = []
    @State private var cursor = ""
    @State private var loading = false
    @State private var error = ""
    var body: some View {
        List {
            Picker("配对状态", selection: $state) { Text("进行中").tag("active"); Text("已结束").tag("unmatched") }.pickerStyle(.segmented)
            ForEach(items) { item in
                NavigationLink { ChatView(matchID: item.id, name: item.name) } label: {
                    HStack(spacing: 12) {
                        AvatarView(media: item.avatar)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(item.name).fontWeight(item["unreadCount"].int > 0 ? .semibold : .regular); Spacer(); if let date = item["lastMessage"]["createdAt"].date { Text(date, style: .time).font(.caption2).foregroundStyle(.secondary) } }
                            HStack { Text(preview(item["lastMessage"])).font(.subheadline).foregroundStyle(.secondary).lineLimit(1); Spacer(); if item["unreadCount"].int > 0 { Text("\(item["unreadCount"].int)").font(.caption.bold()).padding(5).background(.tint, in: Circle()).foregroundStyle(.white) } }
                        }
                    }.padding(.vertical, 4)
                }
            }
            if loading { ProgressView() }
            if !loading && items.isEmpty && error.isEmpty { Text("暂无配对，去探索认识新朋友吧。").foregroundStyle(.secondary) }
            if !error.isEmpty { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(reset: true) } } }
            if !cursor.isEmpty { Button("加载更多") { Task { await load(reset: false) } } }
        }
        .navigationTitle("配对")
        .task(id: "\(state)-\(store.eventVersion)") { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true; defer { loading = false }; error = ""
        do {
            var q = ["state": state]; if !reset && !cursor.isEmpty { q["cursor"] = cursor }
            let data = try await store.get("/matches", query: q)
            items = reset ? data.items : dedup(items + data.items); cursor = data["nextCursor"].string
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func preview(_ value: JSON) -> String {
        if !value.present { return "新的配对" }
        if value["recalled"].bool { return "消息已撤回" }
        switch value["type"].string { case "image": return "图片"; case "voice": return "语音"; case "vrc_link": return "VRChat 链接"; case "system": return "系统消息"; default: return value["text"].string }
    }
}

struct ChatView: View {
    let matchID: String
    let name: String
    @Environment(AppStore.self) private var store
    @State private var detail = JSON.null
    @State private var messages: [Item] = []
    @State private var draft = ""
    @State private var loading = false
    @State private var sending = false
    @State private var pendingSendID: String?
    @State private var pendingSendText = ""
    @State private var hasMore = false
    @State private var error = ""
    @State private var translated: [String: String] = [:]
    @State private var photo: PhotosPickerItem?
    @State private var pendingMedia: UploadDraft?
    @State private var sheet: WebDestination?
    @State private var recording: RecordingRoute?
    @State private var closeConfirmation = false
    @FocusState private var composing: Bool
    var maySend: Bool {
        detail.present && detail["state"].string == "active" && !detail["closedReason"].present &&
        !(detail["boundary"]["required"].bool && !detail["boundary"]["myAck"].bool) && store.me["status"].string != "restricted"
    }
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if loading && messages.isEmpty { ProgressView() }
                    if hasMore { Button("更早的消息") { Task { await loadOlder() } } }
                    if detail["boundary"]["required"].bool && !detail["boundary"]["myAck"].bool { boundaryPanel }
                    ForEach(messages) { item in
                        MessageBubble(message: item, mine: item["senderId"].string == store.me["id"].string, translation: translated[item.id])
                            .id(item.id)
                            .contextMenu {
                                if !item["text"].string.isEmpty { Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = item["text"].string } }
                                if !item["recalled"].bool && item["type"].string == "text" {
                                    Button("翻译", systemImage: "translate") { Task { do { let r = try await store.mutate("/messages/\(item.id)/translate", body: .object(["targetLang": .string("zh-Hant")])); translated[item.id] = r["text"].string } catch { self.error = error.localizedDescription } } }
                                }
                                if item["senderId"].string == store.me["id"].string && !item["recalled"].bool {
                                    Button("撤回", systemImage: "arrow.uturn.backward", role: .destructive) { Task { do { _ = try await store.mutate("/messages/\(item.id)/recall"); await reload() } catch { self.error = error.localizedDescription } } }
                                }
                            }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.last?.id) { _, _ in if sending || composing { withAnimation { reader.scrollTo("bottom", anchor: .bottom) } } }
            .onChange(of: composing) { _, value in if value { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { reader.scrollTo("bottom", anchor: .bottom) } } } }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
        .navigationTitle(detail["user"]["displayName"].string.isEmpty ? name : detail["user"]["displayName"].string)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("分享 VRChat 链接", systemImage: "gamecontroller") { Task { do { let item = try await store.mutate("/matches/\(matchID)/vrc-share"); messages = mergeMessages(messages, [Item(item)]); persist() } catch { self.error = error.localizedDescription } } }
                    Button("历史消息与完整聊天", systemImage: "clock") { sheet = WebDestination(title: "完整聊天", path: "/matches/" + matchID) }
                    Button("举报及资料操作", systemImage: "flag") { sheet = WebDestination(title: "聊天操作", path: "/matches/" + matchID) }
                    Button("结束配对", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { closeConfirmation = true }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task { store.activeMatchID = matchID; messages = MessageCache.load(account: store.me["id"].string, match: matchID); await reload() }
        .task(id: store.eventVersion) { await reload() }
        .onDisappear { if store.activeMatchID == matchID { store.activeMatchID = nil } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
                    pendingMedia = UploadDraft(data: jpeg, filename: "image.jpg", mime: "image/jpeg", purpose: "chat_image", type: "image")
                    photo = nil
                } catch { self.error = error.localizedDescription }
            }
        }
        .sheet(item: $pendingMedia) { draft in UploadView(draft: draft, matchID: matchID) { media in Task { await send(type: draft.type, media: media) } } }
        .sheet(item: $recording) { _ in VoiceRecorderView { data in pendingMedia = UploadDraft(data: data, filename: "voice.m4a", mime: "audio/mp4", purpose: "chat_voice", type: "voice") } }
        .sheet(item: $sheet) { WebPage(destination: $0) }
        .confirmationDialog("结束这个配对？", isPresented: $closeConfirmation, titleVisibility: .visible) {
            Button("结束配对", role: .destructive) { Task { do { _ = try await store.mutate("/matches/" + matchID, method: "DELETE"); await reload() } catch { self.error = error.localizedDescription } } }
        }
    }
    @ViewBuilder private var composer: some View {
        VStack(spacing: 8) {
            if !error.isEmpty { HStack { Text(error).font(.caption).foregroundStyle(.red); Spacer(); Button("关闭") { error = "" } }.padding(.horizontal) }
            if maySend {
                HStack(alignment: .bottom, spacing: 12) {
                    PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo").font(.title3) }.disabled(sending)
                    Button { composing = false; recording = RecordingRoute() } label: { Image(systemName: "mic").font(.title3) }.disabled(sending)
                    TextField("消息", text: $draft, axis: .vertical).lineLimit(1...5).focused($composing)
                        .padding(.horizontal, 12).padding(.vertical, 9).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                    NativeSendButton(busy: sending, disabled: sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000) { Task { await send(type: "text") } }
                }.padding(.horizontal).padding(.vertical, 10)
            } else if detail.present { Text(detail["boundary"]["required"].bool && !detail["boundary"]["myAck"].bool ? "请先阅读并确认对方的边界" : "此会话目前不能发送消息").font(.footnote).foregroundStyle(.secondary).padding() }
        }.background(.bar)
    }
    private var boundaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("对方的边界", systemImage: "hand.raised").font(.headline)
            if detail["boundary"]["peer"].present {
                ForEach(["yes", "maybe", "no"], id: \.self) { level in
                    let limits = detail["boundary"]["peer"]["limits"].array.filter { $0["level"].string == level }
                    if !limits.isEmpty { Text((level == "yes" ? "接受：" : level == "maybe" ? "需要协商：" : "不接受：") + limits.map { $0["item"].string }.joined(separator: "、")) }
                }
                if !detail["boundary"]["peer"]["safeword"].string.isEmpty { Text("安全词：" + detail["boundary"]["peer"]["safeword"].string).bold() }
            } else { Text("此部分内容当前不可见。可以在完整聊天页面查看。") }
            Button("我已阅读并同意遵守") { Task { do { _ = try await store.mutate("/matches/\(matchID)/boundary-ack"); await reload() } catch { self.error = error.localizedDescription } } }
                .buttonStyle(.borderedProminent)
        }.padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    private func reload() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            async let d = store.get("/matches/" + matchID)
            async let m = store.get("/matches/\(matchID)/messages", query: ["limit": "50"])
            let (data, history) = try await (d, m)
            detail = data; messages = mergeMessages(messages, history.items); hasMore = history["hasMore"].bool
            error = ""; persist()
            if let last = messages.last, !store.demo { _ = try? await store.client.request("/matches/\(matchID)/read", method: "POST", body: .object(["lastMessageId": .string(last.id)])) }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func loadOlder() async {
        guard let first = messages.first else { return }
        do { let history = try await store.get("/matches/\(matchID)/messages", query: ["before": first.id, "limit": "50"]); messages = mergeMessages(messages, history.items); hasMore = history["hasMore"].bool; persist() }
        catch { self.error = error.localizedDescription }
    }
    private func send(type: String, media: JSON = .null) async {
        guard !sending, maySend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == "text" && (text.isEmpty || text.count > 2000) { return }
        sending = true; defer { sending = false }
        if type == "text", pendingSendText != text { pendingSendID = nil }
        if pendingSendID == nil { pendingSendID = UUID().uuidString }
        pendingSendText = text
        var body: [String: JSON] = ["clientId": .string(pendingSendID!), "type": .string(type)]
        if type == "text" { body["text"] = .string(text) } else { body["mediaId"] = media["id"] }
        do {
            let item = try await store.mutate("/matches/\(matchID)/messages", body: .object(body))
            messages = mergeMessages(messages, [Item(item)]); persist()
            if type == "text", draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
            pendingSendID = nil
            error = ""
        } catch { self.error = error.localizedDescription }
    }
    private func persist() { if !store.demo { MessageCache.save(messages, account: store.me["id"].string, match: matchID) } }
}

struct MessageBubble: View {
    let message: Item
    let mine: Bool
    let translation: String?
    var body: some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if message["recalled"].bool { Text("消息已撤回").italic().foregroundStyle(.secondary) }
                else {
                    switch message["type"].string {
                    case "image": MediaView(media: message["media"], height: 180).frame(width: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                    case "voice": AudioMessage(media: message["media"])
                    case "vrc_link": if let url = URL(string: message["text"].string), ["https", "vrchat"].contains(url.scheme) { Link("VRChat 链接", destination: url) }
                    case "system": Text("系统消息：" + message["text"].string).font(.caption).foregroundStyle(.secondary)
                    default: Text(message["text"].string).textSelection(.enabled)
                    }
                }
                if let translation { Divider(); Text(translation).font(.subheadline).foregroundStyle(.secondary) }
                if let date = message["createdAt"].date { Text(date, style: .time).font(.caption2).foregroundStyle(.secondary) }
            }.padding(12).background(mine ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            if !mine { Spacer(minLength: 40) }
        }
    }
}

enum MessageCache {
    private static func url(account: String, match: String) -> URL? {
        guard !account.isEmpty, !match.isEmpty, !account.contains("/"), !match.contains("/"), account != "..", match != ".." else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("NativeMessages").appendingPathComponent(account).appendingPathComponent(match + ".json")
    }
    static func load(account: String, match: String) -> [Item] {
        guard let url = url(account: account, match: match), let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([JSON].self, from: data) else { return [] }
        return values.map(Item.init)
    }
    static func save(_ messages: [Item], account: String, match: String) {
        guard let url = url(account: account, match: match), let data = try? JSONEncoder().encode(messages.map(\.value)) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch { /* Server history remains available; do not log message contents. */ }
    }
}
