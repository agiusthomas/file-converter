import SwiftUI
import AppKit
import ConverterCore

private enum Theme {
    static let accent = Color(red: 0.86, green: 0.29, blue: 0.12)
    static let paper = Color(nsColor: .windowBackgroundColor)
    static let warm = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let ink = Color.primary
}

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 202)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let message = model.message {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                                Text(message).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                                Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            }.padding(14).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                        switch model.page {
                        case .convert: conversionPage
                        case .activity: activityPage
                        case .settings: settingsPage
                        }
                    }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.paper)
        .tint(Theme.accent)
        .frame(minWidth: 930, minHeight: 650)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 39, height: 39).background(Theme.accent, in: RoundedRectangle(cornerRadius: 13))
                Text("File\nConverter").font(.system(size: 15, weight: .semibold)).lineSpacing(-1)
            }.padding(.bottom, 38)
            Text("WORKSPACE").font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 10)
            navigation(.convert, icon: "arrow.left.arrow.right")
            navigation(.activity, icon: "clock.arrow.circlepath")
            Text("PREFERENCES").font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(.secondary).padding(.leading, 12).padding(.top, 27).padding(.bottom, 10)
            navigation(.settings, icon: "slider.horizontal.3")
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) { Circle().fill(.green).frame(width: 5, height: 5); Text("All on your Mac").font(.system(size: 11, weight: .medium)) }
                Text("No uploads. No waiting room.").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(12)
        }.padding(.horizontal, 15).padding(.top, 28).padding(.bottom, 20)
        .frame(maxHeight: .infinity).background(Theme.warm.opacity(0.6))
    }
    private func navigation(_ page: WorkspacePage, icon: String) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 19)
                Text(page.rawValue).font(.system(size: 12, weight: model.page == page ? .semibold : .medium))
                Spacer()
                if page == .activity, model.activeCount > 0 {
                    Text("\(model.activeCount)").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accent.opacity(0.12), in: Capsule())
                }
            }.foregroundStyle(model.page == page ? Theme.accent : .primary)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(model.page == page ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.bottom, 4)
    }
    private var header: some View {
        HStack {
            Text(model.page == .convert ? "IMAGE CONVERSION" : model.page.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: model.wheelEnabled ? "circle.inset.filled" : "circle")
                    .foregroundStyle(model.wheelEnabled ? Theme.accent : .secondary)
                Text(model.wheelEnabled ? "Shift wheel on" : "Shift wheel paused")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            Button { model.pickFiles() } label: { Label("Add images", systemImage: "plus") }
                .buttonStyle(.bordered).padding(.leading, 14)
        }.padding(.horizontal, 28).frame(height: 66)
    }
    private var conversionPage: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("A new format.\nOne fluid gesture.")
                        .font(.system(size: 31, weight: .semibold, design: .rounded)).tracking(-0.8).lineSpacing(0)
                    Text("Hold Shift while dragging an image in Finder.\nDrop onto a format in the conversion wheel.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                    HStack(spacing: 7) {
                        Text("⇧").font(.system(size: 20, weight: .medium)).frame(width: 34, height: 32)
                            .background(.background, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.primary.opacity(0.1)))
                        Text("+ drag an image").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }.padding(.top, 2)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                WheelIllustration(formats: model.registry.writableFormats).frame(width: 258, height: 232)
                    .background(Theme.warm, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityLabel("Conversion wheel illustration. Hold Shift and drag an image in Finder.")
            }
            FileDropZone(model: model).frame(height: 126)
            if !model.sources.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("\(model.sources.count) \(model.sources.count == 1 ? "image" : "images") ready").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("Clear selection") { model.sources = [] }.buttonStyle(.link).font(.system(size: 11))
                    }
                    HStack(spacing: 8) {
                        ForEach(model.sources.prefix(3), id: \.self) { url in
                            HStack(spacing: 6) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 21, height: 21)
                                Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                            }.padding(8).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if model.sources.count > 3 { Text("+\(model.sources.count - 3)").font(.caption).foregroundStyle(.secondary) }
                    }
                    HStack(alignment: .center, spacing: 16) {
                        Text("Convert to").font(.system(size: 11)).foregroundStyle(.secondary)
                        Picker("Output format", selection: $model.selectedFormat) {
                            ForEach(model.formats) { format in Text(format.title).tag(format) }
                        }.labelsHidden().frame(width: 125)
                        Spacer()
                        Button { model.onShowWheel?(model.sources) } label: { Label("Open wheel", systemImage: "circle.hexagongrid") }.buttonStyle(.bordered)
                        Button { model.convertSelection() } label: {
                            Label("Convert \(model.sources.count == 1 ? "image" : "images")", systemImage: "arrow.right")
                        }.buttonStyle(.borderedProminent).disabled(model.formats.isEmpty || model.isCancelling)
                    }
                }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.07)))
            }
            HStack(spacing: 18) {
                Label("Originals stay safe", systemImage: "checkmark.shield")
                Label("Saved beside your files", systemImage: "folder")
                Spacer()
                Text("\(model.registry.writableFormats.count) output formats").font(.system(size: 10, weight: .medium))
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            recentActivity
        }
    }
    @ViewBuilder private var recentActivity: some View {
        if !model.jobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent activity").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("View all") { model.page = .activity }.buttonStyle(.link).font(.system(size: 11))
                }
                ForEach(model.jobs.suffix(3).reversed()) { job in JobRow(job: job, reveal: model.reveal) }
            }.padding(.top, 4)
        }
    }
    private var activityPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your conversions.").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(model.completedCount) saved · \(model.activeCount) in progress · \(model.failedCount) need attention")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear finished") { model.clearFinished() }.disabled(model.jobs.isEmpty)
                Button("Show results") { model.revealAll() }.disabled(model.completedCount == 0)
            }
            if model.jobs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 35, weight: .light)).foregroundStyle(.secondary)
                    Text("A clean slate.").font(.system(size: 17, weight: .medium))
                    Text("Finished conversions and their saved files appear here.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Choose images") { model.pickFiles() }.buttonStyle(.bordered).padding(.top, 7)
                }.frame(maxWidth: .infinity).padding(.vertical, 90)
            } else {
                ForEach(model.jobs.reversed()) { job in JobRow(job: job, reveal: model.reveal) }
            }
        }
    }
    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Make it yours.").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Conversion defaults and the Finder shortcut.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            settingsCard("FINDER SHORTCUT") {
                Toggle(isOn: $model.wheelEnabled) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Shift-drag conversion wheel").font(.system(size: 13, weight: .medium))
                        Text("Hold Shift while dragging a supported image in Finder. Choose an output by dropping onto the wheel.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.toggleStyle(.switch)
            }
            settingsCard("IMAGE DEFAULTS") {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle(isOn: $model.preserveMetadata) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Copy supported metadata").font(.system(size: 13, weight: .medium))
                            Text("Keep supported camera and image information when the output format allows it.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.switch)
                    Divider()
                    HStack {
                        Text("Image quality").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(Int(model.quality * 100))%").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent)
                    }
                    Slider(value: $model.quality, in: 0.1...1, step: 0.05).accessibilityLabel("Image quality")
                    Text("Applies to lossy formats such as JPG and HEIC.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            settingsCard("SAVING RESULTS") {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 24)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Right next to the original.").font(.system(size: 13, weight: .medium))
                        Text("Existing names get a number. If macOS blocks saving, allow the folder here and try the conversion again.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Allow a folder…") { model.allowOutputFolder() }.padding(.top, 6)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("AVAILABLE IN THIS BUILD").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Text(model.registry.writableFormats.map(\.title).joined(separator: "  ·  ")).font(.system(size: 11, weight: .medium, design: .monospaced))
                Text("Image conversion foundation · v0.1.0").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.07)))
    }
    private var footer: some View {
        VStack(spacing: 0) {
            if model.isProcessing { ProgressView(value: model.progress).progressViewStyle(.linear).tint(Theme.accent) }
            HStack(spacing: 7) {
                Image(systemName: model.isProcessing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .foregroundStyle(model.isProcessing ? Theme.accent : .secondary)
                Text(model.isProcessing ? "\(model.activeCount) \(model.activeCount == 1 ? "image" : "images") in progress" : "Ready when you are")
                Spacer()
                if model.isProcessing {
                    Button(model.isCancelling ? "Cancelling…" : "Cancel queue") { model.cancel() }.disabled(model.isCancelling).buttonStyle(.link)
                } else {
                    Text("Originals are never replaced")
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 28).frame(height: 36)
        }.background(Theme.warm.opacity(0.35))
    }
}

private struct JobRow: View {
    let job: ConversionJob
    let reveal: (URL) -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if job.state == .running { ProgressView().controlSize(.small).frame(width: 30, height: 30) }
                else {
                    Image(systemName: job.state == .succeeded ? "checkmark" : job.state == .failed ? "exclamationmark" : job.state == .cancelled ? "xmark" : "clock")
                        .font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
                        .foregroundStyle(job.state == .failed ? .red : job.state == .succeeded ? .green : .secondary)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(job.source.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(job.format.title).foregroundStyle(Theme.accent)
                }.font(.system(size: 11, weight: .medium))
                Text(job.detail).font(.system(size: 10)).foregroundStyle(job.state == .failed ? .red : .secondary).fixedSize(horizontal: false, vertical: true)
                if !job.notices.isEmpty { Text(job.notices.joined(separator: " ")).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let output = job.output {
                Button { reveal(output) } label: { Image(systemName: "folder") }.buttonStyle(.plain).help("Show \(output.lastPathComponent) in Finder")
            }
        }.padding(13).background(.background, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.primary.opacity(0.06)))
    }
}

private struct WheelIllustration: View {
    let formats: [ImageFormat]
    var body: some View {
        GeometryReader { proxy in
            let items = Array(formats.prefix(6))
            let centre = CGPoint(x: proxy.size.width / 2, y: 109)
            ZStack {
                ForEach(Array(items.enumerated()), id: \.offset) { index, format in
                    let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(items.count)
                    PreviewPetal(index: index, count: items.count)
                        .fill(index == 0 ? Theme.accent : Color(nsColor: .controlBackgroundColor))
                        .overlay(PreviewPetal(index: index, count: items.count).stroke(.white.opacity(0.8), lineWidth: 1))
                    Text(format.title).font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(index == 0 ? .white : .secondary)
                        .position(x: centre.x + cos(angle) * 69, y: centre.y + sin(angle) * 69)
                }
                VStack(spacing: 1) { Text("⇧").font(.system(size: 27, weight: .medium)); Text("DRAG").font(.system(size: 7, weight: .semibold)).tracking(1) }
                    .foregroundStyle(Theme.accent).position(centre)
                Text("A shortcut around your files.").font(.system(size: 10)).foregroundStyle(.secondary).position(x: centre.x, y: 216)
            }
        }.accessibilityHidden(true)
    }
}

private struct PreviewPetal: Shape {
    let index: Int
    let count: Int
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: 109)
        let step = 360 / Double(max(1, count))
        let start = -90 + Double(index) * step - step / 2 + 3
        let end = -90 + Double(index) * step + step / 2 - 3
        var path = Path()
        path.addArc(center: centre, radius: 95, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: centre, radius: 34, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath(); return path
    }
}

private final class DropHighlight: ObservableObject { @Published var active = false }
private struct FileDropZone: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> FileDropSurface { FileDropSurface(model: model) }
    func updateNSView(_ nsView: FileDropSurface, context: Context) {}
}

@MainActor private final class FileDropSurface: NSView {
    private let highlight = DropHighlight()
    private let model: AppModel
    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        let host = NSHostingView(rootView: DropArtwork(highlight: highlight, choose: { model.pickFiles() }))
        host.translatesAutoresizingMaskIntoConstraints = false; addSubview(host)
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: leadingAnchor), host.trailingAnchor.constraint(equalTo: trailingAnchor), host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = DragMonitor.files(from: sender.draggingPasteboard)
        highlight.active = !model.registry.destinations(for: urls).isEmpty
        return highlight.active ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlight.active = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { highlight.active }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = DragMonitor.files(from: sender.draggingPasteboard)
        highlight.active = false; model.setSources(urls); return !urls.isEmpty
    }
}

private struct DropArtwork: View {
    @ObservedObject var highlight: DropHighlight
    var choose: () -> Void
    var body: some View {
        Button(action: choose) {
            HStack(spacing: 15) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 27, weight: .light)).foregroundStyle(Theme.accent)
                    .frame(width: 56, height: 56).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 6) {
                    Text(highlight.active ? "Let go to add your images" : "Drop images here").font(.system(size: 15, weight: .semibold))
                    Text("or click to choose · one image or a whole batch").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.accent.opacity(highlight.active ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent.opacity(highlight.active ? 0.7 : 0.25), style: StrokeStyle(lineWidth: 1.2, dash: [5, 5])))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Choose images, or drop images here")
    }
}
