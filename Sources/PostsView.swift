import SwiftUI

struct PostsView: View {
    @Environment(AppStore.self) private var store
    @State private var items: [Item] = []
    @State private var query = ""
    @State private var sort = "new"
    @State private var cursor = ""
    @State private var loading = false
    @State private var error = ""
    @State private var sheet: WebDestination?
    var body: some View {
        List {
            ForEach(items) { post in
                NavigationLink { PostDetailView(id: post.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post["title"].string).font(.headline)
                        Text(post["body"].string).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        HStack { Text(post.user["displayName"].string); Spacer(); Label("\(post["likeCount"].int)", systemImage: "heart"); Label("\(post["commentCount"].int)", systemImage: "bubble") }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
            if loading { ProgressView() }
            if items.isEmpty && !loading && error.isEmpty { Text("暂无帖子").foregroundStyle(.secondary) }
            if !error.isEmpty { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(reset: true) } } }
            if !cursor.isEmpty { Button("加载更多") { Task { await load(reset: false) } } }
        }
        .navigationTitle("广场").searchable(text: $query, prompt: "搜索帖子")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu {
            Button("最新") { sort = "new" }; Button("热门") { sort = "hot" }
            Button("发布帖子", systemImage: "square.and.pencil") { sheet = WebDestination(title: "发布帖子", path: "/posts/new") }
            Button("分类与完整广场") { sheet = WebDestination(title: "广场", path: "/posts") }
        } label: { Image(systemName: "ellipsis") } } }
        .task(id: "\(query)-\(sort)-\(store.mode.rawValue)") { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { await load(reset: true) } }
        .refreshable { await load(reset: true) }
        .sheet(item: $sheet) { WebPage(destination: $0) }
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true; defer { loading = false }; error = ""
        do {
            var q = ["sort": sort]; if !query.isEmpty { q["q"] = query }; if !reset && !cursor.isEmpty { q["cursor"] = cursor }
            let result = try await store.get("/posts", query: q)
            items = reset ? result.items : dedup(items + result.items); cursor = result["nextCursor"].string
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct PostDetailView: View {
    let id: String
    @Environment(AppStore.self) private var store
    @State private var post = JSON.null
    @State private var comments: [Item] = []
    @State private var cursor = ""
    @State private var draft = ""
    @State private var error = ""
    @State private var sending = false
    @State private var sheet: WebDestination?
    var body: some View {
        List {
            if post.present {
                Section {
                    Text(post["title"].string).font(.title2.bold())
                    Text(post["body"].string).textSelection(.enabled)
                    ForEach(Array(post["media"].array.enumerated()), id: \.offset) { _, media in MediaView(media: media, height: 220) }
                    Button(post["liked"].bool ? "取消喜欢" : "喜欢", systemImage: post["liked"].bool ? "heart.fill" : "heart") {
                        Task { do { _ = try await store.mutate("/posts/\(id)/like", method: post["liked"].bool ? "DELETE" : "POST"); await load() } catch { self.error = error.localizedDescription } }
                    }
                }
                Section("评论") {
                    ForEach(comments) { item in
                        VStack(alignment: .leading, spacing: 6) { Text(item.name).font(.caption).foregroundStyle(.secondary); Text(item["body"].string); ForEach(item["replies"].array.map(Item.init)) { reply in Text(reply.name + "：" + reply["body"].string).font(.subheadline).foregroundStyle(.secondary) } }
                    }
                    if !cursor.isEmpty { Button("更多评论") { Task { await moreComments() } } }
                }
            } else if error.isEmpty { ProgressView() }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Button("完整帖子与编辑、举报操作") { sheet = WebDestination(title: "完整帖子", path: "/posts/" + id) }
        }
        .navigationTitle("帖子").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("写评论", text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                Button("发送") { sendComment() }.disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding().background(.bar)
        }
        .task { await load() }.refreshable { await load() }
        .sheet(item: $sheet) { WebPage(destination: $0) }
    }
    private func load() async {
        do { post = try await store.get("/posts/" + id); let c = try await store.get("/posts/\(id)/comments"); comments = c.items; cursor = c["nextCursor"].string; error = "" }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func moreComments() async {
        do { let c = try await store.get("/posts/\(id)/comments", query: ["cursor": cursor]); comments = dedup(comments + c.items); cursor = c["nextCursor"].string } catch { self.error = error.localizedDescription }
    }
    private func sendComment() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines); sending = true
        Task {
            defer { sending = false }
            do { _ = try await store.mutate("/posts/\(id)/comments", body: .object(["body": .string(body)])); if draft.trimmingCharacters(in: .whitespacesAndNewlines) == body { draft = "" }; await load() }
            catch { self.error = error.localizedDescription }
        }
    }
}
