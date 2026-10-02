import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .badge] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            if let id = response.notification.request.content.userInfo["matchID"] as? String {
                NotificationCenter.default.post(name: .init("OpenNativeMatch"), object: id)
            }
        }
    }
}

@main
struct VRCRPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environment(store)
                .task { await store.bootstrap() }
                .onChange(of: scenePhase) { _, phase in store.lifecycle(active: phase == .active) }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var selected = 0
    @State private var sheet: WebDestination?
    @State private var notificationMatch: MatchRoute? = ProcessInfo.processInfo.arguments.contains("--preview-chat") ? MatchRoute(id: "demo-match") : nil
    var body: some View {
        Group {
            switch store.phase {
            case .loading: ProgressView("正在连接…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loggedOut:
                ContentUnavailableView {
                    Label("vrcrp", systemImage: "bubble.left.and.bubble.right")
                } description: { Text("登录你的账号，开始探索与聊天。") } actions: {
                    Button("登录或注册") { sheet = WebDestination(title: "登录", path: "/login", login: true) }.buttonStyle(.borderedProminent)
                }
            case .failed: ErrorPane(message: store.error) { Task { await store.bootstrap() } }
            case .ready:
                TabView(selection: $selected) {
                    NavigationStack { ExploreView() }.tabItem { Label("探索", systemImage: "safari") }.tag(0)
                    NavigationStack { PeopleListView(kind: .likes) }.tabItem { Label("喜欢", systemImage: "heart") }.tag(1)
                    NavigationStack { MatchesView() }.tabItem { Label("配对", systemImage: "bubble.left.and.bubble.right") }.badge(store.counters["unreadMessages"].int).tag(2)
                    NavigationStack { PostsView() }.tabItem { Label("广场", systemImage: "rectangle.stack") }.tag(3)
                    NavigationStack { AccountView() }.tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
                }
            }
        }
        .sheet(item: $sheet) { WebPage(destination: $0) }
        .sheet(item: $notificationMatch) { route in NavigationStack { ChatView(matchID: route.id, name: "聊天") } }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenNativeMatch"))) { event in
            if let id = event.object as? String { selected = 2; notificationMatch = MatchRoute(id: id) }
        }
    }
}

struct MatchRoute: Identifiable { let id: String }

struct ErrorPane: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView { Label("暂时无法加载", systemImage: "wifi.exclamationmark") }
            description: { Text(message) } actions: { Button("重试", action: retry) }
    }
}

struct MediaView: View {
    let media: JSON
    var height: CGFloat = 180
    var body: some View {
        Group {
            if media["view"].present && media["view"].string != "show" {
                Image(systemName: "eye.slash").font(.largeTitle).foregroundStyle(.secondary)
            } else if let url = URL(string: media["thumbUrl"].string.isEmpty ? media["url"].string : media["thumbUrl"].string), ["https"].contains(url.scheme) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() }
            } else { Image(systemName: "person.crop.circle").font(.system(size: height * 0.4)).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .background(Color(.secondarySystemBackground)).clipped()
    }
}

struct AvatarView: View {
    let media: JSON
    var size: CGFloat = 48
    var body: some View { MediaView(media: media, height: size).frame(width: size).clipShape(Circle()) }
}
