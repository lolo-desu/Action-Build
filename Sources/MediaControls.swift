import SwiftUI
import AVFoundation
import Observation

struct UploadDraft: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
    let mime: String
    let purpose: String
    let type: String
}
struct RecordingRoute: Identifiable { let id = UUID() }

struct UploadView: View {
    let draft: UploadDraft
    let matchID: String
    let onUploaded: (JSON) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rating = "general"
    @State private var realPerson = false
    @State private var uploading = false
    @State private var error = ""
    @State private var sheet: WebDestination?
    var body: some View {
        NavigationStack {
            Form {
                if draft.type == "image", let image = UIImage(data: draft.data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).listRowBackground(Color.clear) }
                Section("媒体信息") {
                    Picker("内容分级", selection: $rating) { Text("普通").tag("general"); Text("暗示性内容").tag("suggestive") }
                    if draft.type == "image" { Toggle("包含真人", isOn: $realPerson) }
                    LabeledContent("文件大小", value: ByteCountFormatter.string(fromByteCount: Int64(draft.data.count), countStyle: .file))
                }
                Section { Button("成人分级与其他上传选项") { sheet = WebDestination(title: "完整上传", path: "/matches/" + matchID) } }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(draft.type == "image" ? "发送图片" : "发送语音").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(uploading) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(uploading ? "上传中…" : "发送") {
                        uploading = true
                        Task {
                            defer { uploading = false }
                            do {
                                let media = try await store.client.upload(draft.data, filename: draft.filename, mime: draft.mime, purpose: draft.purpose, matchID: matchID, rating: rating, realPerson: realPerson)
                                dismiss(); onUploaded(media)
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(uploading || store.demo)
                }
            }
            .sheet(item: $sheet) { WebPage(destination: $0) }
            .interactiveDismissDisabled(uploading)
        }
    }
}

@MainActor @Observable
final class Recorder {
    var recording = false
    var seconds = 0
    var error = ""
    var url: URL?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    func start() async {
        let granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        guard granted else { error = "请在 iOS 设置中允许麦克风访问。"; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let r = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
            guard r.record(forDuration: 120) else { throw URLError(.cannotCreateFile) }
            recorder = r; url = file; recording = true; seconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; self.seconds += 1; if self.seconds >= 120 { self.stop() } }
            }
        } catch { self.error = error.localizedDescription }
    }
    func stop() { recorder?.stop(); recording = false; timer?.invalidate(); timer = nil; try? AVAudioSession.sharedInstance().setActive(false) }
    func cleanup() { stop(); if let url { try? FileManager.default.removeItem(at: url) }; url = nil }
}

struct VoiceRecorderView: View {
    let onDone: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = Recorder()
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Image(systemName: recorder.recording ? "waveform" : "mic.circle").font(.system(size: 70)).symbolEffect(.pulse, isActive: recorder.recording)
                Text(String(format: "%02d:%02d", recorder.seconds / 60, recorder.seconds % 60)).font(.system(.largeTitle, design: .monospaced))
                if !recorder.error.isEmpty { Text(recorder.error).foregroundStyle(.red) }
                Button(recorder.recording ? "停止录音" : "开始录音") { if recorder.recording { recorder.stop() } else { Task { await recorder.start() } } }.buttonStyle(.borderedProminent)
                if !recorder.recording, let url = recorder.url {
                    LocalAudioButton(url: url)
                    Button("继续发送") {
                        guard let data = try? Data(contentsOf: url) else { return }
                        dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onDone(data) }
                    }.buttonStyle(.bordered)
                }
                Text("最长 2 分钟").font(.footnote).foregroundStyle(.secondary)
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("录制语音").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .onDisappear { recorder.cleanup() }
        }
    }
}

struct LocalAudioButton: View {
    let url: URL
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    var body: some View {
        Button(playing ? "暂停试听" : "试听", systemImage: playing ? "pause.fill" : "play.fill") {
            if playing { player?.pause(); playing = false }
            else {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                try? AVAudioSession.sharedInstance().setActive(true)
                if player == nil { player = try? AVAudioPlayer(contentsOf: url) }
                player?.play(); playing = true
            }
        }.onDisappear { player?.stop() }
    }
}

struct AudioMessage: View {
    let media: JSON
    @State private var player: AVPlayer?
    @State private var playing = false
    var body: some View {
        Button(playing ? "暂停语音" : "播放语音", systemImage: playing ? "pause.fill" : "play.fill") {
            if playing { player?.pause(); playing = false }
            else if let url = URL(string: media["url"].string), url.scheme == "https", media["view"].string != "hide", media["view"].string != "blur" {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                try? AVAudioSession.sharedInstance().setActive(true)
                if player == nil { player = AVPlayer(url: url) }
                player?.play(); playing = true
            }
        }.onDisappear { player?.pause() }
    }
}
