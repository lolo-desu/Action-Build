import SwiftUI

struct ProfileView: View {
    let id: String
    @Environment(AppStore.self) private var store
    @State private var profile = JSON.null
    @State private var error = ""
    @State private var working = false
    @State private var sheet: WebDestination?
    @State private var match: MatchRoute?
    @State private var confirmBlock = false
    var body: some View {
        List {
            if !profile.present && error.isEmpty { ProgressView() }
            if profile.present {
                Section {
                    MediaView(media: profile["cover"], height: 260).listRowInsets(EdgeInsets())
                    Text(profile["displayName"].string).font(.title2.bold())
                    if !profile["tagline"].string.isEmpty { Text(profile["tagline"].string) }
                }
                Section("关于") {
                    if !profile["bio"].string.isEmpty { Text(profile["bio"].string).textSelection(.enabled) }
                    LabeledContent("语言", value: profile["languages"].array.map(\.string).joined(separator: "、"))
                    if !profile["timezone"].string.isEmpty { LabeledContent("时区", value: profile["timezone"].string) }
                    if !profile["intents"].array.isEmpty { LabeledContent("意向", value: profile["intents"].array.map(\.string).joined(separator: "、")) }
                    if !profile["tags"].array.isEmpty { Text(profile["tags"].array.map { $0["name"].string.isEmpty ? $0.string : $0["name"].string }.joined(separator: " · ")) }
                }
                if !profile["photos"].array.isEmpty {
                    Section("照片") { ForEach(Array(profile["photos"].array.enumerated()), id: \.offset) { _, photo in MediaView(media: photo, height: 220) } }
                }
                if id != store.me["id"].string {
                    Section {
                        if profile["relation"]["matchState"].string == "active" {
                            Button("发送消息", systemImage: "bubble.left") { match = MatchRoute(id: profile["relation"]["matchId"].string) }
                        } else {
                            HStack {
                                Button("跳过", systemImage: "xmark") { swipe("pass") }
                                Spacer()
                                Button("喜欢", systemImage: "heart") { swipe("like") }
                            }.disabled(working || profile["relation"]["swiped"].string == "like" || profile["paused"].bool)
                        }
                        Button("超级喜欢及完整操作") { sheet = WebDestination(title: "资料", path: "/u/" + id) }
                    }
                }
                Section {
                    Button("留言与完整资料") { sheet = WebDestination(title: "完整资料", path: "/u/" + id) }
                    if id != store.me["id"].string {
                        Button("屏蔽此用户", role: .destructive) { confirmBlock = true }
                        Button("举报") { sheet = WebDestination(title: "举报与资料操作", path: "/u/" + id) }
                    }
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } }
        }
        .navigationTitle(profile["displayName"].string.isEmpty ? "资料" : profile["displayName"].string)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
        .sheet(item: $sheet) { WebPage(destination: $0) }
        .sheet(item: $match) { route in NavigationStack { ChatView(matchID: route.id, name: profile["displayName"].string) } }
        .confirmationDialog("屏蔽此用户？", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("屏蔽", role: .destructive) { Task { do { _ = try await store.mutate("/users/\(id)/block"); await load() } catch { self.error = error.localizedDescription } } }
        } message: { Text("双方将无法继续互动。你可以在设置中解除屏蔽。") }
    }
    private func load() async {
        do { profile = try await store.get("/profiles/" + id); error = "" } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func swipe(_ action: String) {
        working = true
        Task {
            defer { working = false }
            do {
                let result = try await store.mutate("/swipes", body: .object(["targetId": .string(id), "action": .string(action)]))
                if result["matched"].bool { match = MatchRoute(id: result["match"]["id"].string) }
                await load()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct EditProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tagline = ""
    @State private var bio = ""
    @State private var loaded = false
    @State private var saving = false
    @State private var error = ""
    @State private var sheet: WebDestination?
    var body: some View {
        Form {
            Section("基本资料") { TextField("显示名称", text: $name); TextField("一句话介绍", text: $tagline); TextField("个人介绍", text: $bio, axis: .vertical).lineLimit(5...14) }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Section { Button("照片、模型、标签及完整资料编辑") { sheet = WebDestination(title: "完整资料编辑", path: "/profile/edit") } }
        }
        .navigationTitle("编辑资料").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中…" : "保存") { save() }.disabled(!loaded || saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
        .task {
            do { let p = try await store.get("/me/profile"); name = p["displayName"].string; tagline = p["tagline"].string; bio = p["bio"].string; loaded = true }
            catch { self.error = error.localizedDescription }
        }
        .sheet(item: $sheet) { WebPage(destination: $0) }
    }
    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do { _ = try await store.mutate("/me/profile", method: "PATCH", body: .object(["displayName": .string(name), "tagline": .string(tagline), "bio": .string(bio)])); await store.bootstrap(); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
