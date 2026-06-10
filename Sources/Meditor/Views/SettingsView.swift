import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTheme") private var defaultThemeRaw = MermaidTheme.default.rawValue
    @AppStorage("editorFontName") private var editorFontName = "SF Mono"
    @AppStorage("editorFontSize") private var editorFontSize = 14.0
    @AppStorage("wrapLines") private var wrapsLines = false
    @AppStorage("defaultExportScale") private var exportScaleRaw = ExportScale.two.rawValue
    @AppStorage("transparentExport") private var transparentExport = true
    @State private var showsLicenses = false

    var body: some View {
        Form {
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
                Toggle("Transparent background when possible", isOn: $transparentExport)
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
}
