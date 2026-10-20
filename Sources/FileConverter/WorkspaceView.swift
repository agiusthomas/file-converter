import SwiftUI
import AppKit
import ConverterCore
import UniformTypeIdentifiers
import QuickLookUI

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var dropActive = false
    @State private var recipeName = ""
    @State private var pageSelection = ""
    @State private var targetMB = ""
    @State private var resize = ""
    @State private var trimEnd = ""
    @State private var crop = ""
    @State private var editingRecipe: Recipe?
    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:190); Divider()
            VStack(spacing:0) {
                HStack {
                    Text(model.page.rawValue.uppercased()).font(.system(size:10,weight:.semibold)).tracking(1.8).foregroundStyle(.secondary)
                    Spacer()
                    Label(model.wheelEnabled ? "\(model.modifier.capitalized) wheel on" : "Wheel paused",systemImage:"circle.hexagongrid").font(.system(size:11)).foregroundStyle(.secondary)
                    Button { model.pickFiles() } label:{ Label("Add files",systemImage:"plus") }.buttonStyle(GlacierActionStyle())
                }.padding(.horizontal,26).frame(height:66)
                Divider()
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        if let message = model.message {
                            HStack(alignment:.top) { Image(systemName:"info.circle"); Text(message).font(.callout); Spacer(); Button { model.message = nil } label:{ Image(systemName:"xmark") }.buttonStyle(.plain) }.padding(14).background(Theme.accent.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                        }
                        switch model.page {
                        case .convert: conversion
                        case .activity: activity
                        case .recipes: recipes
                        case .shelf: shelf
                        case .engines: engines
                        case .settings: settings
                        }
                    }.padding(26).frame(maxWidth:.infinity,alignment:.leading)
                }
                Divider()
                HStack {
                    if model.isProcessing { ProgressView().controlSize(.small); Text("\(model.activeCount) jobs in progress"); Spacer(); Button("Cancel jobs") { model.cancel() }.disabled(model.isCancelling) }
                    else { Label("All on your Mac",systemImage:"checkmark.shield"); Spacer(); Text("Originals stay intact") }
                }.font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,26).frame(height:42)
            }
        }.foregroundStyle(Theme.ink).background(Theme.paper).tint(Theme.accent).frame(minWidth:930,minHeight:650)
        .sheet(item:$editingRecipe) { recipe in RecipeEditor(recipe:recipe,packs:model.packs) { model.saveEditedRecipe($0) } }
        .onChange(of:model.sources) { _ in pageSelection = "" }

    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:7) {
            Label("File Converter",systemImage:"arrow.triangle.2.circlepath").font(.system(size:17,weight:.semibold)).padding(.bottom,30)
            ForEach(WorkspacePage.allCases,id:\.self) { page in
                Button { model.page = page } label: {
                    HStack(spacing:10) { Image(systemName:icon(page)).frame(width:20); Text(page.rawValue); Spacer(); if page == .activity && model.activeCount > 0 { Text("\(model.activeCount)").font(.caption2) } }
                        .font(.system(size:12,weight:model.page == page ? .semibold : .regular)).padding(12)
                        .foregroundStyle(model.page == page ? Theme.accent : Theme.ink)
                        .background { if model.page == page { GlacierGlass(shape:RoundedRectangle(cornerRadius:10)) } }
                }.buttonStyle(.plain)
            }
            Spacer(); Text("Convert. Prepare. Share.").font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(18).frame(maxHeight:.infinity).background { GlacierSidebarSurface() }
    }
    private func icon(_ page: WorkspacePage) -> String { switch page { case .convert:return "arrow.left.arrow.right"; case .activity:return "clock"; case .recipes:return "slider.horizontal.3"; case .shelf:return "tray.full"; case .engines:return "shippingbox"; case .settings:return "gearshape" } }
    private var conversion: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:12) {
                    Text("Your files.\nReady for what’s next.").font(.system(size:30,weight:.semibold,design:.rounded))
                    Text("Convert, compress, combine, and extract.\nHold \(model.modifier.capitalized) while dragging files in Finder for quick actions.").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5)
                }; Spacer()
                WheelArtwork(formats:model.registry.writableFormats,selected:0,title:"⇧",subtitle:"DRAG",showsFormatLabels:true).frame(width:205,height:205)
            }
            Button { model.pickFiles() } label: {
                HStack(spacing:18) {
                    Image(systemName:"doc.on.doc").font(.system(size:28,weight:.light)).foregroundStyle(Theme.accent)
                    VStack(alignment:.leading,spacing:6) { Text(dropActive ? "Drop to inspect your files" : "Drop files or folders here").font(.system(size:15,weight:.semibold)); Text("Images, PDFs, audio, video, text, subtitles, and archives").font(.system(size:11)).foregroundStyle(.secondary) }
                    Spacer(); Image(systemName:"plus")
                }.padding(24).frame(maxWidth:.infinity).background { GlacierGlass(shape:RoundedRectangle(cornerRadius:16)) }
                    .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(Theme.accent.opacity(dropActive ? 1 : 0.4),style:StrokeStyle(lineWidth:dropActive ? 2 : 1,dash:[5,5])))
            }.buttonStyle(.plain)
            .onDrop(of:[UTType.fileURL.identifier],isTargeted:$dropActive) { providers in
                let group = DispatchGroup(); let collector = DropCollector()
                for (index,provider) in providers.enumerated() { group.enter(); _ = provider.loadObject(ofClass:URL.self) { url,_ in if let url { collector.append(url,index:index) }; group.leave() } }
                group.notify(queue:.main) { model.setSources(collector.urls) }; return true
            }
            if model.isInspecting { HStack { ProgressView().controlSize(.small); Text("Inspecting file contents…").font(.callout) } }
            if !model.sources.isEmpty {
                HStack { Text("\(model.sources.count) files selected").font(.headline); Spacer(); Button("Clear") { model.setSources([]) } }
                if model.assets.count == 1, model.assets[0].format == "folder" { Button("Convert files inside this folder…") { model.expandSelectedFolders() } }
                if Set(model.assets.map(\.family)).count > 1 {
                    HStack { Text("Show a family:").font(.caption); ForEach(FileFamily.allCases.filter { family in model.assets.contains(where:{$0.family == family}) },id:\.self) { family in Button(family.rawValue.capitalized) { model.setSources(model.assets.filter {$0.family == family}.map(\.source)) }.font(.caption) } }
                    Text("Only actions shared by the whole selection are offered below.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.assets) { asset in
                    Button { model.previewURL = asset.source } label: {
                        HStack {
                            Image(nsImage:NSWorkspace.shared.icon(forFile:asset.source.path)).resizable().frame(width:26,height:26)
                            VStack(alignment:.leading,spacing:4) {
                                Text(asset.source.lastPathComponent).font(.system(size:12,weight:.medium)).lineLimit(1)
                                Text(details(asset)).font(.system(size:10)).foregroundStyle(.secondary)
                                if !asset.notices.isEmpty { Text(asset.notices.joined(separator:" ")).font(.caption2).foregroundStyle(.secondary) }
                            }; Spacer(); Image(systemName:"eye").foregroundStyle(.secondary)
                        }.padding(10).modifier(GlacierCard(radius:10))
                    }.buttonStyle(.plain)
                }
                if !model.actions.isEmpty {
                    VStack(alignment:.leading,spacing:16) {
                        Picker("Action",selection:Binding(get:{model.selectedAction},set:model.selectAction)) {
                            ForEach(model.actions) { action in Text(action.title + (action.available ? "" : " · pack required")).tag(action.id) }
                        }
                        Picker("Output",selection:$model.selectedProfileID) { ForEach(model.profiles) { profile in Text(profile.title).tag(profile.id) } }
                        if let limitation = model.action?.limitation { Label(limitation,systemImage:"info.circle").font(.caption).foregroundStyle(.secondary) }
                        if model.action?.available == false {
                            HStack { Text("Install the \(model.action?.requiredPack?.capitalized ?? "required") pack to enable this action.").font(.callout); Spacer(); Button("View engines") { model.page = .engines } }
                        } else { operationOptions }
                        TextField("Filename template (optional): {name}-{format}-{index}",text:optionalString(\.filenameTemplate))
                        if model.options.filenameTemplate != nil, let profile = model.selectedProfile {
                            Text(model.sources.prefix(3).enumerated().compactMap { index,url in try? NamingPolicy.stem(template:model.options.filenameTemplate,source:url,profile:profile,index:index+1) + (profile.fileExtension.isEmpty ? "" : "." + profile.fileExtension) }.joined(separator:"  ·  ")).font(.caption).foregroundStyle(.secondary)
                        }
                        if let root = model.relativeSourceRoot { Label("Preserve subfolders from \(root.lastPathComponent) when a destination is selected",systemImage:"folder").font(.caption).foregroundStyle(.secondary) }
                        if let formIssue { Label(formIssue,systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.red) }
                        HStack {
                            Button(model.destination?.lastPathComponent ?? "Save beside originals") { model.chooseDestination() }
                            if model.destination != nil { Button("Reset") { model.destination = nil }.buttonStyle(.link) }
                            Spacer(); Button("Open wheel") { model.onShowWheel?(model.sources) }
                            Button(model.isPreviewing ? "Preparing preview…" : "Preview result") { model.previewResult() }.disabled(model.isPreviewing || model.isProcessing || model.action?.available != true || formIssue != nil)
                            Button("Run action") { model.convertSelection() }.buttonStyle(GlacierActionStyle(prominent:true)).disabled(model.action?.available != true || model.isInspecting || model.isCancelling || formIssue != nil)
                        }.font(.system(size:11))
                        HStack { TextField("Name this recipe",text:$recipeName); Button("Save recipe") { model.saveRecipe(name:recipeName); recipeName = "" }.disabled(recipeName.trimmingCharacters(in:.whitespaces).isEmpty) }
                    }.padding(18).modifier(GlacierCard())
                }
                if let url = model.previewURL { DisclosureGroup("File preview") { FilePreview(url:url).frame(height:340).clipShape(RoundedRectangle(cornerRadius:10)) } }
                if let result = model.resultPreviewURL, let source = model.sources.first {
                    VStack(alignment:.leading,spacing:10) {
                        Text("Before and after · \(model.previewSummary ?? "")").font(.headline)
                        HStack { VStack { Text("Original").font(.caption); FilePreview(url:source).frame(height:280) }; VStack { Text("Result").font(.caption); FilePreview(url:result).frame(height:280) } }
                    }.padding(14).modifier(GlacierCard())
                }
            }
            if model.sources.isEmpty, let url = model.previewURL { FilePreview(url:url).frame(height:340).clipShape(RoundedRectangle(cornerRadius:10)) }
            if !model.jobs.isEmpty { Text("Recent activity").font(.headline); ForEach(model.jobs.suffix(3).reversed()) { job in JobRow(job:job,model:model) } }
        }
    }
    @ViewBuilder private var operationOptions: some View {
        let action = model.selectedAction
        if [.imageConvert,.pdfExport,.pdfCompress].contains(action) {
            HStack { Text("Quality"); Slider(value:$model.options.quality,in:0.1...1,step:0.05); Text("\(Int(model.options.quality*100))%").monospacedDigit() }.font(.caption)
        }
        if [.imageConvert,.mediaConvert,.pdfCompress].contains(action) {
            HStack {
                TextField("Target size in MB (optional)",text:$targetMB).onChange(of:targetMB) { value in model.options.targetBytes = Double(value).flatMap { $0.isFinite && $0 > 0 && $0 < 1000000 ? Int64($0*1024*1024) : nil } }
                Menu("Sharing presets") {
                    Button("Smaller file") { model.options.quality = 0.75; model.options.maximumDimension = 1920; resize = "1920" }
                    Button("Email · under 10 MB") { targetMB = "10"; model.options.allowDownscale = true }
                    Button("Compatible image") { model.selectAction(.imageConvert); model.selectedProfileID = "jpg"; model.options.preserveMetadata = false }
                    Button("Compatible video") { model.selectAction(.mediaConvert); model.selectedProfileID = "mp4-h264" }
                }
            }
        }
        if [.imageConvert,.imagesToPDF,.mediaConvert].contains(action) {
            HStack {
                TextField("Maximum dimension (pixels)",text:$resize).onChange(of:resize) { value in model.options.maximumDimension = Int(value) }
                Picker("Rotate",selection:$model.options.rotation) { ForEach([0,90,180,270],id:\.self) { Text("\($0)°").tag($0) } }.frame(width:160)
            }
            if action != .mediaConvert { TextField("Crop: x,y,width,height (pixels)",text:$crop).onChange(of:crop) { value in let parts = value.split(separator:",").compactMap { Int($0.trimmingCharacters(in:.whitespaces)) }; model.options.crop = parts.count == 4 ? CropRect(x:parts[0],y:parts[1],width:parts[2],height:parts[3]) : nil } }
        }
        if action == .imageConvert {
            Toggle("Allow downscaling to reach target size",isOn:$model.options.allowDownscale)
            Toggle("Copy supported metadata",isOn:$model.options.preserveMetadata)
            Toggle("Remove GPS image properties and verify",isOn:$model.options.removeLocation)
            TextField("Background hex color",text:$model.options.background)
            DisclosureGroup("Additional outputs") {
                ForEach(model.profiles.filter { $0.id != model.selectedProfileID }) { profile in Toggle(profile.title,isOn:Binding(get:{ model.additionalProfiles.contains(profile.id) },set:{ if $0 { model.additionalProfiles.insert(profile.id) } else { model.additionalProfiles.remove(profile.id) } })) }
            }
        }
        if model.assets.contains(where: { $0.family == .pdf }) {
            SecureField("Opening password (if needed)",text:optionalString(\.inputPassword))
            TextField("Pages in output order, e.g. 3,1,2 (empty = all)",text:$pageSelection).onChange(of:pageSelection) { value in model.options.pages = value.split(separator:",").compactMap { Int($0.trimmingCharacters(in:.whitespaces)) } }
            if action == .pdfOrganize { Picker("Rotate selected pages",selection:$model.options.rotation) { ForEach([0,90,180,270],id:\.self) { Text("\($0)°").tag($0) } } }
            if [.pdfOrganize,.pdfSplit,.pdfExport].contains(action), model.sources.count == 1 {
                Button(model.isLoadingPages ? "Loading pages…" : "Load page thumbnails") { model.loadPageThumbnails() }.disabled(model.isLoadingPages || model.isProcessing)
                if !model.pageThumbnails.isEmpty { pageOrganizer }
            }
        }
        if [.pdfExport,.pdfOCR,.pdfCompress,.imagesToPDF].contains(action) {
            HStack { Text("Resolution"); Stepper("\(Int(model.options.dpi)) DPI",value:$model.options.dpi,in:36...600,step:36) }.font(.caption)
        }
        if action == .imagesToPDF {
            Picker("Page size",selection:Binding(get:{model.options.pageWidth == nil ? "image" : model.options.pageWidth == 595 ? "a4" : "letter"},set:{ value in model.options.pageWidth = value == "image" ? nil : value == "a4" ? 595 : 612; model.options.pageHeight = value == "image" ? nil : value == "a4" ? 842 : 792 })) { Text("Fit image").tag("image"); Text("A4").tag("a4"); Text("US Letter").tag("letter") }
            HStack { Text("Margin (points)"); TextField("Margin",value:$model.options.margin,format:.number); Toggle("Fill page (crop edges)",isOn:$model.options.fillPage) }
        }
        if action == .pdfProtect { SecureField("New opening password",text:optionalString(\.outputPassword)) }
        if [.mediaConvert,.mediaExtractAudio,.mediaFrame].contains(action) {
            HStack { Text("Start (seconds)"); TextField("Start",value:$model.options.startTime,format:.number); TextField("End (optional)",text:$trimEnd).onChange(of:trimEnd) { model.options.endTime = Double($0) } }
            if action != .mediaFrame {
                HStack { Picker("Speed",selection:$model.options.speed) { ForEach([0.5,1,1.5,2],id:\.self) { Text("\($0,specifier:"%.1f")×").tag($0) } }; Toggle("Mute",isOn:$model.options.mute) }
                if model.selectedProfile?.videoCodec == nil || model.packs.contains(where:{$0.id == "media"}) {
                    HStack { Picker("Channels",selection:$model.options.channels) { Text("Mono").tag(1); Text("Stereo").tag(2) }; Picker("Sample rate",selection:$model.options.sampleRate) { ForEach([16000,44100,48000,96000],id:\.self) { Text("\($0) Hz").tag($0) } } }
                    TextField("Audio bitrate (bits per second)",value:$model.options.bitrate,format:.number)
                } else { Text("Movie audio uses automatic native settings. The Media pack enables exact audio controls.").font(.caption).foregroundStyle(.secondary) }
                Toggle("Copy compatible streams without re-encoding",isOn:$model.options.streamCopy)
                if model.packs.contains(where: { $0.id == "media" }) { Toggle("Normalize loudness",isOn:$model.options.normalizeLoudness) }
            }
        }
        if [.textConvert,.subtitleConvert].contains(action) {
            Picker("Input encoding",selection:$model.options.sourceEncoding) { ForEach(["auto","utf-8","utf-16","windows-1252","ascii"],id:\.self) { Text($0.uppercased()).tag($0) } }
            HStack { Picker("Encoding",selection:$model.options.encoding) { ForEach(["utf-8","utf-16","windows-1252","ascii"],id:\.self) { Text($0.uppercased()).tag($0) } }; Picker("Line endings",selection:$model.options.lineEndings) { Text("LF").tag("lf"); Text("CRLF").tag("crlf") } }
        }
        if action == .subtitleConvert { HStack { Text("Timing offset (seconds)"); TextField("Offset",value:$model.options.subtitleOffset,format:.number) } }
        if action == .documentConvert, model.assets.contains(where:{$0.family == .spreadsheet}) {
            TextField("Sheet number (empty = all sheets)",text:optionalString(\.sheet))
            TextField("CSV delimiter",text:$model.options.delimiter)
            Text("Delimited exports contain displayed values. Formulas, formatting, and workbook features are not retained.").font(.caption).foregroundStyle(.secondary)
        }
        if action == .archiveExtract, let asset = model.assets.first {
            DisclosureGroup("Choose archive members (all by default)") {
                ForEach(asset.members.prefix(250),id:\.self) { name in Toggle(name,isOn:Binding(get:{model.options.archiveMembers.contains(name)},set:{ if $0 { model.options.archiveMembers.append(name) } else { model.options.archiveMembers.removeAll { $0 == name } } })).font(.caption) }
                if asset.members.count > 250 { Text("Showing the first 250 members. The default extracts all members.").font(.caption) }
            }
        }
        if [.pdfOCR,.imageConvert].contains(action) { Toggle("Clean up scan contrast and page perspective",isOn:$model.options.scanCleanup) }
        if [.pdfOCR,.transcribe].contains(action) { TextField("Language code (auto by default)",text:$model.options.language) }
    }
    private var pageOrganizer: some View {
        let pages = model.options.pages.isEmpty ? Array(1...model.pageThumbnails.count) : model.options.pages
        return VStack(alignment:.leading,spacing:10) {
            HStack { Text("Pages in output order").font(.caption.bold()); Spacer(); Button("Restore all pages") { model.options.pages = Array(1...model.pageThumbnails.count) } }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:120))],spacing:12) {
                ForEach(Array(pages.enumerated()),id:\.offset) { position,page in
                    if page > 0 && page <= model.pageThumbnails.count {
                        VStack(spacing:6) {
                            if let image = NSImage(contentsOf:model.pageThumbnails[page-1]) { Image(nsImage:image).resizable().scaledToFit().frame(height:100).rotationEffect(.degrees(Double(model.options.pageRotations[page] ?? 0))) }
                            Text("Page \(page)").font(.caption)
                            HStack(spacing:10) {
                                Button { guard position > 0 else { return }; model.options.pages = pages; model.options.pages.swapAt(position,position-1) } label:{Image(systemName:"arrow.left")}.disabled(position == 0)
                                Button { model.options.pageRotations[page] = ((model.options.pageRotations[page] ?? 0)+90)%360 } label:{Image(systemName:"rotate.right")}
                                Button { model.options.pages = pages; model.options.pages.remove(at:position) } label:{Image(systemName:"minus.circle")}.disabled(pages.count <= 1)
                                Button { guard position+1 < pages.count else { return }; model.options.pages = pages; model.options.pages.swapAt(position,position+1) } label:{Image(systemName:"arrow.right")}.disabled(position+1 == pages.count)
                            }.buttonStyle(.borderless).font(.caption)
                        }.padding(10).modifier(GlacierCard(radius:10))
                    }
                }
            }
        }
    }
    private var formIssue: String? {
        let action = model.selectedAction
        if !targetMB.isEmpty, [.imageConvert,.mediaConvert,.pdfCompress].contains(action), Double(targetMB).map({ $0.isFinite && $0 > 0 && $0 < 1000000 }) != true { return "Enter a positive target size in MB." }
        if !resize.isEmpty, [.imageConvert,.imagesToPDF,.mediaConvert].contains(action), Int(resize).map({(1...100000).contains($0)}) != true { return "Enter a maximum dimension from 1 to 100,000 pixels." }
        if !trimEnd.isEmpty, [.mediaConvert,.mediaExtractAudio,.mediaFrame].contains(action), Double(trimEnd).map({$0.isFinite && $0 > model.options.startTime}) != true { return "Trim end must be later than the start." }
        if !crop.isEmpty, [.imageConvert,.imagesToPDF].contains(action) {
            let parts = crop.split(separator:",",omittingEmptySubsequences:false)
            if parts.count != 4 || parts.contains(where:{Int($0.trimmingCharacters(in:.whitespaces)) == nil}) { return "Crop needs four integers: x, y, width, height." }
        }
        if !pageSelection.isEmpty, model.assets.contains(where:{$0.family == .pdf}) {
            let parts = pageSelection.split(separator:",",omittingEmptySubsequences:false)
            if parts.contains(where:{ Int($0.trimmingCharacters(in:.whitespaces)).map({$0 > 0}) != true }) { return "Pages must be positive numbers separated by commas." }
        }
        do { var settings = model.options; settings.minimumQuality = min(settings.minimumQuality,settings.quality); _ = try settings.validated() }
        catch { return error.localizedDescription }
        return nil
    }
    private func optionalString(_ key: WritableKeyPath<OperationOptions,String?>) -> Binding<String> { Binding(get:{model.options[keyPath:key] ?? ""},set:{model.options[keyPath:key] = $0.isEmpty ? nil : $0}) }
    private func details(_ asset: AssetDescriptor) -> String {
        var parts = [asset.family.rawValue.capitalized,asset.format.uppercased(),ByteCountFormatter.string(fromByteCount:asset.byteCount,countStyle:.file)]
        if let width = asset.width, let height = asset.height { parts.append("\(width) × \(height)") }
        if let pages = asset.pageCount { parts.append("\(pages) pages / frames") }
        if let duration = asset.duration { parts.append(String(format:"%.1f seconds",duration)) }
        if !asset.tracks.isEmpty { parts.append(asset.tracks.joined(separator:", ")) }
        if let profile = asset.metadata?["colorProfile"] { parts.append(profile) }
        if let depth = asset.metadata?["bitDepth"] { parts.append(depth + " bit") }
        return parts.joined(separator:" · ")
    }
    private var activity: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { VStack(alignment:.leading,spacing:6) { Text("Your conversions.").font(.system(size:28,weight:.semibold,design:.rounded)); Text("\(model.completedCount) saved · \(model.activeCount) active · \(model.failedCount) need attention").font(.callout).foregroundStyle(.secondary) }; Spacer(); Button("Clear finished") { model.clearFinished() }; Button("Show results") { model.revealAll() } }
            if model.jobs.isEmpty { Text("Converted files and interrupted jobs appear here.").foregroundStyle(.secondary).padding(.vertical,50) }
            ForEach(model.jobs.reversed()) { job in JobRow(job:job,model:model) }
        }
    }
    private var recipes: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("Ready-made routines.").font(.system(size:28,weight:.semibold,design:.rounded)); Spacer(); Button("New recipe") { editingRecipe = Recipe(name:"New recipe",steps:[.init(action:.imageConvert,profiles:[ActionCatalog.png],export:true)]) }; Button("Import…") { model.importRecipe() } }
            Text("Choose files in Convert, then run a recipe. Save your current options there to create a new recipe.").font(.callout).foregroundStyle(.secondary)
            ForEach(model.recipes) { recipe in HStack { VStack(alignment:.leading,spacing:5) { Text(recipe.name).font(.headline); Text("\(recipe.steps.count) steps · \(recipe.steps.last?.profiles.map(\.title).joined(separator:", ") ?? "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Edit") { editingRecipe = recipe }; Button("Export…") { model.exportRecipe(recipe) }; Button("Run on selection") { model.runRecipe(recipe) }.disabled(model.sources.isEmpty || model.isProcessing); Button { model.recipes.removeAll { $0.id == recipe.id }; model.persistRecipes() } label:{ Image(systemName:"trash") } }.padding(16).modifier(GlacierCard()) }
            Text("Watched folders").font(.title3.bold())
            Text("Only new or changed files are processed after they settle. Results go into a Converted subfolder. Existing files are skipped when a watcher starts.").font(.caption).foregroundStyle(.secondary)
            Menu("Add watched folder…") { ForEach(model.recipes) { recipe in Button(recipe.name) { model.addWatchRule(recipe) } } }
            ForEach(model.watchRules.indices,id:\.self) { index in
                VStack(alignment:.leading,spacing:10) {
                    Toggle("\(model.watchRules[index].folder.lastPathComponent) · \(model.watchRules[index].recipe.name)",isOn:Binding(get:{model.watchRules[index].enabled},set:{model.watchRules[index].enabled = $0; model.restartWatchers()}))
                    HStack { TextField("Extensions, separated by commas",text:Binding(get:{model.watchRules[index].extensions.joined(separator:",")},set:{model.watchRules[index].extensions = $0.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces).lowercased() }; model.restartWatchers()})); Button("Remove rule") { model.watchRules.remove(at:index); model.restartWatchers() } }
                }.padding(14).modifier(GlacierCard())
            }
        }
    }
    private var shelf: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Keep files within reach.").font(.system(size:28,weight:.semibold,design:.rounded))
            Text("Save results here from Activity, then drag them into another app.").font(.callout).foregroundStyle(.secondary)
            ForEach(model.shelf,id:\.self) { url in HStack { Text(url.lastPathComponent).font(.headline); Spacer(); Button("Copy") { model.copy(url) }; Button("Show in Finder") { model.reveal(url) }; Button("Remove from shelf") { model.shelf.removeAll { $0 == url }; model.persistShelf() } }.padding(16).modifier(GlacierCard()).onDrag { NSItemProvider(contentsOf:url) ?? NSItemProvider() } }
        }
    }
    private var engines: some View { EngineLibraryView(model:model) }
    private var settings: some View {
        VStack(alignment:.leading,spacing:22) {
            Text("Make it yours.").font(.system(size:28,weight:.semibold,design:.rounded))
            VStack(alignment:.leading,spacing:16) {
                Toggle("Finder conversion wheel",isOn:$model.wheelEnabled)
                Picker("Wheel modifier",selection:$model.modifier) { Text("Shift").tag("shift"); Text("Option").tag("option"); Text("Control").tag("control") }
                Toggle("Open at login",isOn:Binding(get:{model.launchAtLogin},set:model.setLogin))
            }.padding(18).modifier(GlacierCard())
            VStack(alignment:.leading,spacing:14) { Text("Output access").font(.headline); Text("Results are saved beside originals unless you choose another folder. Existing names receive a number.").font(.callout).foregroundStyle(.secondary); HStack { Button("Allow a folder…") { model.allowOutputFolder() }; Button("Revoke saved folder access") { FolderGrants.shared.revokeAll(); model.destination = nil } } }.padding(18).modifier(GlacierCard())
            Text("File Converter · development 0.2.0\nJob history stays on this Mac. Passwords are excluded from saved jobs and recipes.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
private struct JobRow: View {
    let job: JobRecord; @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack(alignment:.top) {
                Image(systemName:job.state == .succeeded ? "checkmark.circle.fill" : [.failed,.interrupted].contains(job.state) ? "exclamationmark.circle" : "clock").foregroundStyle(job.state == .succeeded ? .green : Theme.accent)
                VStack(alignment:.leading,spacing:5) { Text(job.request.inputs.map(\.lastPathComponent).joined(separator:", ")).font(.system(size:12,weight:.medium)).lineLimit(2); Text("\(job.request.action.rawValue) · \(job.state.rawValue.capitalized)").font(.caption).foregroundStyle(.secondary); if let error = job.error { Text(error).font(.caption).foregroundStyle(.red) } }
                Spacer(); if [.failed,.cancelled,.interrupted].contains(job.state) { Button("Retry") { model.retry(job) }.disabled(model.isCancelling) }
            }
            if let manifest = job.manifest {
                ForEach(manifest.outputs) { output in
                    HStack { Text(output.url.lastPathComponent).font(.caption); Text(ByteCountFormatter.string(fromByteCount:output.byteCount,countStyle:.file)).font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Preview") { model.previewURL = output.url; model.page = .convert }; Menu { Button("Keep on shelf") { model.shelve(output.url) }; Button("Move generated result to Trash") { model.removeGenerated(output) } } label:{Image(systemName:"ellipsis.circle")}; Button { model.copy(output.url) } label:{Image(systemName:"doc.on.doc")}; Button { model.reveal(output.url) } label:{Image(systemName:"folder")} }.onDrag { NSItemProvider(contentsOf:output.url) ?? NSItemProvider() }
                }
                if !manifest.notices.isEmpty { Text(manifest.notices.joined(separator:" ")).font(.caption2).foregroundStyle(.secondary) }
            }
        }.padding(14).modifier(GlacierCard(radius:12))
    }
}
private struct FilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context:Context) -> QLPreviewView { let view = QLPreviewView(frame:.zero,style:.normal)!; view.autostarts = false; return view }
    func updateNSView(_ view:QLPreviewView,context:Context) { view.previewItem = url as NSURL }
}
private final class DropCollector: @unchecked Sendable {
    private let lock = NSLock(); private var values: [Int:URL] = [:]
    func append(_ url:URL,index:Int) { lock.lock(); values[index] = url; lock.unlock() }
    var urls: [URL] { lock.lock(); defer {lock.unlock()}; return values.sorted {$0.key < $1.key}.map(\.value) }
}
