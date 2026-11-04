import AppKit
import SwiftUI

@MainActor
final class IndicatorModel: ObservableObject {
    @Published var text = ""
    @Published var level: Float = 0
    @Published var handsFree = false
    @Published var finishing = false
    @Published var tidying = false

    func reset() {
        text = ""
        level = 0
        handsFree = false
        finishing = false
        tidying = false
    }
}

/// A small floating capsule at the top of the screen. It never takes focus
/// or mouse events, so the app you're dictating into stays active.
@MainActor
final class IndicatorPanel {
    let model = IndicatorModel()

    private static let size = NSSize(width: 440, height: 64)

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
        return panel
    }()

    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.maxY - Self.size.height - 12))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct IndicatorView: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        HStack(spacing: 14) {
            LevelBars(level: model.finishing ? 0 : model.level)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.text.isEmpty ? "Listening…" : model.text)
                    .font(.callout)
                    .foregroundStyle(model.text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(width: 440, height: 64)
        .background(.regularMaterial, in: Capsule())
    }

    private var hint: String {
        if model.tidying { return "Tidying up on-device…" }
        if model.finishing { return "Inserting…" }
        if model.handsFree { return "Hands-free · press the key again to insert · Esc cancels" }
        return "Release to insert · Esc cancels"
    }
}

private struct LevelBars: View {
    let level: Float
    private let weights: [Float] = [0.5, 0.8, 1, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: CGFloat(6 + 22 * level * weights[index]))
            }
        }
        .frame(width: 32, height: 28)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
