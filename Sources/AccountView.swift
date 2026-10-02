import SwiftUI
import UserNotifications

struct AccountView: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: WebDestination?
    @State private var logoutConfirmation = false
    @State private var error = ""
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    AvatarView(media: store.me["avatar"], size: 68)
                    VStack(alignment: .leading, spacing: 6) { Text(store.me["displayName"].string).font(.title2.bold()); Text("vrcrp").font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 10)
                NavigationLink("查看我的资料") { ProfileView(id: store.me["id"].string) }
                NavigationLink("编辑资料") { EditProfileView() }
            }
            Section {
                NavigationLink { NotificationsView() } label: { Label("通知", systemImage: "bell"); Spacer(); if store.counters["unreadNotifications"].int > 0 { Text("\(store.counters["unreadNotifications"].int)").foregroundStyle(.secondary) } }
                NavigationLink { NativeSettingsView() } label: { Label("设置", systemImage: "gearshape") }
                NavigationLink { PeopleListView(kind: .visitors) } label: { Label("访客", systemImage: "person.2") }
            }
            Section("网站服务") {
                webButton("VRChat 绑定与状态", icon: "gamecontroller", path: "/settings/vrc")
                webButton("能量与交易记录", icon: "bolt", path: "/settings/energy")
                webButton("会员", icon: "star", path: "/settings/membership")
                webButton("邀请朋友", icon: "person.badge.plus", path: "/settings/invite")
                webButton("完整网站", icon: "globe", path: "/")
            }
            Section {
                Button("退出登录", role: .destructive) { logoutConfirmation = true }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("我的")
        .sheet(item: $sheet) { WebPage(destination: $0) }
        .confirmationDialog("退出当前账号？", isPresented: $logoutConfirmation, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { do { try await store.logout() } catch { self.error = error.localizedDescription } } }
        }
    }
    private func webButton(_ title: String, icon: String, path: String) -> some View {
        Button { sheet = WebDestination(title: title, path: path) } label: { Label(title, systemImage: icon) }
    }
}

struct NativeSettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("NativeLocalAlerts") private var alerts = false
    @State private var sheet: WebDestination?
    @State private var error = ""
    var body: some View {
        @Bindable var binding = store
        Form {
            Section("显示") {
                Picker("内容模式", selection: $binding.mode) { ForEach(ContentMode.allCases) { Text($0.title).tag($0) } }
                Text("界面跟随 iOS 的明暗外观和字号设置。").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("聊天通知", isOn: $alerts)
                    .onChange(of: alerts) { _, enabled in
                        if enabled { Task { do { let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); if !granted { alerts = false; error = "请在 iOS 设置中允许 vrcrp 发送通知。" } } catch { alerts = false; self.error = error.localizedDescription } } }
                    }
                Button("iOS 通知设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            } header: { Text("通知") } footer: { Text("接收客户端运行期间的新聊天提醒。锁屏、后台和关闭应用后的推送需要网站提供原生推送服务。") }
            Section("账号与隐私") {
                web("账号安全与登录方式", "/settings/account")
                web("隐私", "/settings/privacy")
                web("内容与媒体设置", "/settings/content")
                web("网站通知与邮件", "/settings/notifications")
                web("屏蔽列表", "/settings/blocks")
                web("语言", "/settings/language")
                web("其他设置", "/settings")
            }
            Section("关于") { LabeledContent("名称", value: "vrcrp"); LabeledContent("版本", value: "2.0 原生预览"); Text("独立第三方客户端，连接原网站账号与数据。").font(.footnote).foregroundStyle(.secondary) }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("设置")
        .sheet(item: $sheet) { WebPage(destination: $0) }
    }
    private func web(_ title: String, _ path: String) -> some View { Button(title) { sheet = WebDestination(title: title, path: path) } }
}

struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @State private var items: [Item] = []
    @State private var cursor = ""
    @State private var loading = false
    @State private var error = ""
    @State private var sheet: WebDestination?
    var body: some View {
        List {
            ForEach(items) { item in
                Button {
                    sheet = WebDestination(title: "通知", path: "/notifications")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item["read"].bool ? "bell" : "bell.badge.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(item["type"].string)).foregroundStyle(.primary)
                            if !item["text"].string.isEmpty { Text(item["text"].string).font(.subheadline).foregroundStyle(.secondary) }
                            if let date = item["createdAt"].date { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if loading { ProgressView() }
            if items.isEmpty && !loading && error.isEmpty { Text("暂无通知").foregroundStyle(.secondary) }
            if !error.isEmpty { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(reset: true) } } }
            if !cursor.isEmpty { Button("加载更多") { Task { await load(reset: false) } } }
        }
        .navigationTitle("通知")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("全部已读") {
                    Task {
                        do {
                            _ = try await store.mutate("/notifications/read", body: .object(["all": .bool(true)]))
                            await load(reset: true)
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        .task(id: store.eventVersion) { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .sheet(item: $sheet) { WebPage(destination: $0) }
    }
    private func title(_ type: String) -> String {
        switch type { case "match", "new_match": "新配对"; case "message", "new_message": "新消息"; case "guestbook": "资料留言"; case "like": "新的喜欢"; default: "网站通知" }
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true; defer { loading = false }; error = ""
        do {
            let result = try await store.get("/notifications", query: !reset && !cursor.isEmpty ? ["cursor": cursor] : [:])
            items = reset ? result.items : dedup(items + result.items); cursor = result["nextCursor"].string
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
