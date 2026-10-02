import SwiftUI

struct NativeSendButton: View {
    let busy: Bool
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) { label }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                .disabled(disabled).accessibilityLabel("发送消息")
        } else {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .disabled(disabled).accessibilityLabel("发送消息")
        }
    }
    private var label: some View {
        Group { if busy { ProgressView() } else { Image(systemName: "arrow.up").font(.headline) } }
            .frame(width: 24, height: 24)
    }
}
