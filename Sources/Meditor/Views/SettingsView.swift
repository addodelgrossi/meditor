import SwiftUI

struct SettingsView: View {
    @AppStorage("appAppearance") private var appAppearanceRaw = AppAppearance.system.rawValue
    @AppStorage("defaultTheme") private var defaultThemeRaw = MermaidTheme.default.rawValue
    @AppStorage("editorFontName") private var editorFontName = "SF Mono"
    @AppStorage("editorFontSize") private var editorFontSize = 14.0
    @AppStorage("wrapLines") private var wrapsLines = false
    @AppStorage("defaultExportScale") private var exportScaleRaw = ExportScale.two.rawValue
    @AppStorage("transparentExport") private var transparentExport = true
    @AppStorage("defaultExportBackground") private var exportBackgroundRaw = ""
    @AppStorage("shareBaseURL") private var shareBaseURL = "https://meditor.dev"
    @State private var shareBaseURLDraft = UserDefaults.standard.string(forKey: "shareBaseURL")
        ?? ShareServiceURL.defaultValue
    @State private var showsLicenses = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("App appearance", selection: appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
            }

            Section("Editor") {
                Picker("Font", selection: $editorFontName) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                }
                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $editorFontSize, in: 11...24, step: 1)
                            .frame(width: 180)
                        Text("\(Int(editorFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Wrap long lines", isOn: $wrapsLines)
            }

            Section("Diagram") {
                Picker("Default theme", selection: $defaultThemeRaw) {
                    ForEach(MermaidTheme.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
            }

            Section("Export") {
                Picker("Default PNG scale", selection: $exportScaleRaw) {
                    ForEach(ExportScale.allCases) { scale in
                        Text(scale.label).tag(scale.rawValue)
                    }
                }
                Picker("Default export background", selection: exportBackground) {
                    ForEach(ExportBackground.allCases) { background in
                        Text(background.label).tag(background)
                    }
                }
            }

            Section("Publish") {
                TextField("Base URL", text: $shareBaseURLDraft, prompt: Text(ShareServiceURL.defaultValue))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: shareBaseURLDraft) { _, newValue in
                        if let serviceURL = try? ShareServiceURL(newValue) {
                            shareBaseURL = serviceURL.string
                        }
                    }
                if (try? ShareServiceURL(shareBaseURLDraft)) == nil {
                    Text("Use HTTPS, or HTTP only for a local development server.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Where the Publish button sends diagrams. Change this to point at your own meditor-cloud instance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About & Legal") {
                LabeledContent("Version", value: AppInfo.versionDescription)
                LabeledContent("Author", value: AppInfo.author)
                Link("Privacy Policy", destination: AppInfo.privacyURL)
                Link("Support", destination: AppInfo.supportURL)
                Link("Source Code", destination: AppInfo.sourceURL)
                Button("Open Source Licenses") {
                    showsLicenses = true
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 610)
        .navigationTitle("Settings")
        .sheet(isPresented: $showsLicenses) {
            LicensesView()
        }
    }

    private var appAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance.resolved(appAppearanceRaw) },
            set: { appAppearanceRaw = $0.rawValue }
        )
    }

    private var exportBackground: Binding<ExportBackground> {
        Binding(
            get: { ExportBackground.resolved(exportBackgroundRaw, legacyTransparent: transparentExport) },
            set: { exportBackgroundRaw = $0.rawValue }
        )
    }
}
