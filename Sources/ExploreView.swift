import SwiftUI

struct ExploreView: View {
    @Environment(AppStore.self) private var store
    @State private var items: [Item] = []
    @State private var loading = false
    @State private var error = ""
    @State private var browse = false
    @State private var cursor = ""
    @State private var sheet: WebDestination?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if loading && items.isEmpty { ProgressView().padding(60) }
                if !error.isEmpty { ErrorPane(message: error) { Task { await load(reset: true) } } }
                if items.isEmpty && !loading && error.isEmpty { ContentUnavailableView("暂时没有更多资料", systemImage: "person.2", description: Text("试试更改筛选条件，或稍后刷新。")) }
                ForEach(items) { person in
                    NavigationLink { ProfileView(id: person.id) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            MediaView(media: person["cover"], height: 240).clipShape(RoundedRectangle(cornerRadius: 24))
                            Text(person["displayName"].string).font(.title2.bold()).foregroundStyle(.primary)
                            Text(person["tagline"].string).foregroundStyle(.secondary).lineLimit(3)
                            Text(person["languages"].array.map(\.string).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                    }.buttonStyle(.plain)
                }
                if !items.isEmpty {
                    Button("加载更多") { Task { await load(reset: false) } }.disabled(loading)
                }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("探索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(browse ? "推荐资料" : "浏览资料", systemImage: "square.grid.2x2") { browse.toggle() }
                    Button("筛选条件", systemImage: "line.3.horizontal.decrease") { sheet = WebDestination(title: "探索筛选", path: "/discover") }
                    Button("撤销上次操作", systemImage: "arrow.uturn.backward") { Task { do { _ = try await store.mutate("/swipes/undo"); await load(reset: true) } catch { self.error = error.localizedDescription } } }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
            }
        }
        .refreshable { await load(reset: true) }
        .task(id: "\(browse)-\(store.mode.rawValue)") { await load(reset: true) }
        .sheet(item: $sheet) { WebPage(destination: $0) }
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true; error = ""
        defer { loading = false }
        do {
            var query = ["limit": "20"]
            if browse { if !reset && !cursor.isEmpty { query["cursor"] = cursor } }
            let result = try await store.get(browse ? "/browse" : "/feed", query: query)
            cursor = result["nextCursor"].string
            items = reset ? result.items : dedup(items + result.items)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

enum PeopleKind: String, CaseIterable, Identifiable {
    case likes, sent, visitors
    var id: String { rawValue }
    var title: String { switch self { case .likes: "喜欢我"; case .sent: "我喜欢的"; case .visitors: "访客" } }
    var endpoint: String { switch self { case .likes: "/likes/received"; case .sent: "/likes/sent"; case .visitors: "/visitors" } }
}

struct PeopleListView: View {
    @Environment(AppStore.self) private var store
    @State var kind: PeopleKind
    @State private var items: [Item] = []
    @State private var cursor = ""
    @State private var loading = false
    @State private var error = ""
    @State private var locked = false
    @State private var sheet: WebDestination?
    var body: some View {
        List {
            Picker("列表", selection: $kind) { ForEach(PeopleKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if locked {
                Label("此列表需要网站会员权限", systemImage: "lock")
                Button("查看会员信息") { sheet = WebDestination(title: "会员", path: "/settings/membership") }
            }
            ForEach(items) { item in
                NavigationLink { ProfileView(id: item.user["id"].string.isEmpty ? item.id : item.user["id"].string) } label: {
                    HStack(spacing: 12) { AvatarView(media: item.avatar); VStack(alignment: .leading) { Text(item.name); Text(item.user["tagline"].string).font(.caption).foregroundStyle(.secondary) } }
                }
            }
            if loading { ProgressView() }
            if !error.isEmpty { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(reset: true) } } }
            if !loading && items.isEmpty && !locked && error.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
            if !cursor.isEmpty { Button("加载更多") { Task { await load(reset: false) } } }
        }
        .navigationTitle("喜欢")
        .task(id: "\(kind.rawValue)-\(store.mode.rawValue)-\(store.eventVersion)") { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .sheet(item: $sheet) { WebPage(destination: $0) }
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true; error = ""; defer { loading = false }
        do {
            let result = try await store.get(kind.endpoint, query: !reset && !cursor.isEmpty ? ["cursor": cursor] : [:])
            locked = result["locked"].bool; cursor = result["nextCursor"].string
            items = reset ? result.items : dedup(items + result.items)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

func dedup(_ items: [Item]) -> [Item] { var seen = Set<String>(); return items.filter { seen.insert($0.id).inserted } }
