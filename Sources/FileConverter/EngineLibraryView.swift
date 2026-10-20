import SwiftUI
import AppKit
import ConverterCore

struct EngineLibraryView: View {
    @ObservedObject var model: AppModel
    private let engines = [("media","Media","Audio and video codecs, filters and loudness normalization"),("documents","Documents","Office, presentations, spreadsheets and Markdown"),("ebooks","Ebooks","Calibre ebook interchange"),("transcription","Transcription","Offline transcription and models"),("pdf","PDF structure","Lossless structural PDF tools")]
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file) }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("More possibilities. Still local.").font(.system(size:28,weight:.semibold,design:.rounded))
            Text("Install only the engines you need. Downloads are explicit; installed engines process your files offline.").font(.callout).foregroundStyle(.secondary)
            if let failure = model.engineFailure { Label(failure,systemImage:"exclamationmark.triangle").font(.callout).foregroundStyle(.red) }
            if model.engineBusyID == "local" {
                HStack { ProgressView().controlSize(.small); Text("Verifying and installing the local pack…").font(.callout); Spacer(); Button("Cancel installation") { model.cancelEngineInstall() } }
            }
            ForEach(engines,id:\.0) { id,title,description in
                engine(id,title:title,description:description)
            }
            HStack {
                Button("Import a signed local pack…") { model.importPack() }.disabled(model.engineBusyID != nil)
                Button("Refresh") { Task { await model.refreshEngineLibrary() } }.disabled(model.engineBusyID != nil)
            }
            Text("Documents, Ebooks, Transcription and PDF packs remain under development until their runtimes and acceptance gates pass.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func engine(_ id: String, title: String, description: String) -> some View {
        let installed = model.storedPacks.first { $0.id == id }
        let entry = model.engineCatalog.filter { $0.id == id }.sorted { $0.version.compare($1.version,options:.numeric) == .orderedDescending }.first
        let incompatible = entry.flatMap { EnginePacks.incompatibility($0) }
        let busy = model.engineBusyID == id
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top) {
                Image(systemName:"shippingbox").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment:.leading,spacing:5) { Text(title).font(.headline); Text(description).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if model.engineRemovals.contains(id) { Text("Removal deferred").font(.caption) }
                else if let installed { Text("Installed · \(installed.manifest.version)").font(.caption) }
                else { Text(incompatible == nil ? (entry == nil ? "Not published" : "Available") : "Incompatible").font(.caption) }
            }
            if let installed {
                Text("Installed size: \(size(installed.manifest.installedBytes))").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Licenses, source and runtime versions") {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(installed.manifest.engineVersions.keys.sorted().filter { $0 != "configuration" },id:\.self) { key in Text("\(key): \(installed.manifest.engineVersions[key] ?? "")").font(.caption) }
                        ForEach(installed.manifest.licenses,id:\.self) { relative in Button(URL(fileURLWithPath:relative).lastPathComponent) { NSWorkspace.shared.open(installed.location.appendingPathComponent(relative)) }.buttonStyle(.link) }
                        Button("Show complete installed runtime") { model.reveal(installed.location) }
                    }.padding(.top,8)
                }.font(.caption)
            }
            if let entry {
                Text("Version \(entry.version) · \(size(entry.downloadBytes)) download" + (entry.installedBytes.map { " · \(size($0)) installed" } ?? "")).font(.caption).foregroundStyle(.secondary)
                if let notice = entry.notice { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                if let incompatible { Label(incompatible,systemImage:"exclamationmark.circle").font(.caption) }
            }
            if busy, let progress = model.engineProgress {
                HStack {
                    if progress.phase == .downloading, progress.totalBytes > 0 {
                        ProgressView(value:Double(progress.receivedBytes),total:Double(progress.totalBytes))
                        Text("\(size(progress.receivedBytes)) / \(size(progress.totalBytes))").font(.caption).monospacedDigit()
                    } else { ProgressView().controlSize(.small); Text(progress.phase.rawValue.capitalized + "…").font(.caption) }
                    Button("Cancel installation") { model.cancelEngineInstall() }
                }.accessibilityElement(children:.combine)
            } else {
                HStack {
                    if let entry, installed.map({ entry.version.compare($0.manifest.version,options:.numeric) == .orderedDescending }) ?? true {
                        Button(installed == nil ? "Download and install" : "Download update") { model.downloadEngine(entry) }.disabled(incompatible != nil || model.engineBusyID != nil)
                    }
                    if let previous = model.engineRollbackVersions[id] { Button("Roll back to \(previous)") { model.rollbackEngine(id) }.disabled(model.isProcessing || model.engineBusyID != nil) }
                    if installed != nil { Button("Remove pack") { model.removeEngine(id) }.disabled(model.isProcessing || model.engineBusyID != nil) }
                    if model.engineRemovals.contains(id) { Button("Retry removal") { Task { await model.refreshEngineLibrary() } } }
                }
            }
        }.padding(18).modifier(GlacierCard())
    }
}
