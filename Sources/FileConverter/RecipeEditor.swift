import SwiftUI
import ConverterCore

struct RecipeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var recipe: Recipe
    let packs: [InstalledEnginePack]
    let save: (Recipe) -> Void
    @State private var issue: String?
    private var actions: [ActionDescriptor] { ActionCatalog.all(installedPacks:Set(packs.map(\.id))).filter { $0.id != .pdfProtect } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Edit recipe").font(.title2.bold())
            TextField("Recipe name",text:$recipe.name)
            Text("Processing steps feed the next step. Exports save a result and keep the current input available for other exports. Use lossless images or audio between steps.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing:14) {
                    ForEach(recipe.steps.indices,id:\.self) { index in
                        VStack(alignment:.leading,spacing:12) {
                            HStack {
                                Text("Step \(index+1)").font(.headline); Spacer()
                                Button { recipe.steps.swapAt(index,index-1) } label:{ Image(systemName:"arrow.up") }.disabled(index == 0)
                                Button { recipe.steps.swapAt(index,index+1) } label:{ Image(systemName:"arrow.down") }.disabled(index+1 == recipe.steps.count)
                                Button { recipe.steps.remove(at:index) } label:{ Image(systemName:"trash") }.disabled(recipe.steps.count <= 1)
                            }
                            Picker("Action",selection:Binding(get:{recipe.steps[index].action},set:{ id in recipe.steps[index].action = id; recipe.steps[index].profiles = actions.first(where:{$0.id == id})?.profiles.prefix(1).map {$0} ?? [] })) {
                                ForEach(actions) { action in Text(action.title + (action.available ? "" : " · pack required")).tag(action.id) }
                            }
                            let profiles = actions.first(where:{$0.id == recipe.steps[index].action})?.profiles ?? []
                            Picker("Output",selection:Binding(get:{recipe.steps[index].profiles.first?.id ?? ""},set:{ id in recipe.steps[index].profiles = profiles.filter {$0.id == id} })) { ForEach(profiles) { Text($0.title).tag($0.id) } }
                            Toggle("Save this result as an export",isOn:$recipe.steps[index].export)
                            if recipe.steps[index].action == .imageConvert {
                                HStack { Text("Quality"); Slider(value:$recipe.steps[index].options.quality,in:0.3...1); Text("\(Int(recipe.steps[index].options.quality*100))%") }
                                Picker("Maximum dimension",selection:Binding(get:{recipe.steps[index].options.maximumDimension ?? 0},set:{ recipe.steps[index].options.maximumDimension = $0 == 0 ? nil : $0 })) { Text("Original size").tag(0); ForEach([640,1280,1920,2560,3840],id:\.self) { Text("\($0) pixels").tag($0) } }
                                Toggle("Copy supported metadata",isOn:$recipe.steps[index].options.preserveMetadata)
                            }
                        }.padding(16).modifier(GlacierCard())
                    }
                }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Add step") { recipe.steps.append(.init(action:.imageConvert,profiles:[ActionCatalog.png],export:true)) }.disabled(recipe.steps.count >= 20)
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save recipe") { do { try recipe.validate(); save(recipe); dismiss() } catch { issue = error.localizedDescription } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width:640,height:650).background(Theme.paper)
    }
}
