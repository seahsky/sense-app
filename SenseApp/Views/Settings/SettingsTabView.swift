import SwiftUI
import SenseKit
import SenseUI

/// Defaults, and the app's own paperwork.
///
/// This is a tab rather than an About row behind the Trend tab's navigation bar
/// because it is going to grow: the acronym the app is named after promises Sets,
/// Effort, Notes and Streaks, and the preferences for those land here.
///
/// The font acknowledgement is not optional decoration. The SIL Open Font License
/// asks in clause 2 that the copyright notice and licence travel with any
/// redistribution of the font, and shipping it inside the binary with no way to
/// read it does not meet that in any meaningful sense.
struct SettingsTabView: View {
    /// Shared with the Watch's own start screen through the same key, so the
    /// preference an athlete sets here is the one the Watch starts with.
    @AppStorage("isAutoCountEnabled") private var isAutoCountEnabled = true
    @AppStorage("defaultVariantRawValue") private var defaultVariantRawValue = CindyVariant.rx.rawValue

    private var defaultVariant: Binding<CindyVariant> {
        Binding(
            get: { CindyVariant(rawValue: defaultVariantRawValue) ?? .rx },
            set: { defaultVariantRawValue = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Auto-count reps", isOn: $isAutoCountEnabled)

                    Picker("Default variant", selection: defaultVariant) {
                        ForEach(CindyVariant.allCases) { variant in
                            Text(variant.displayName).tag(variant)
                        }
                    }
                } header: {
                    Text("Workout")
                } footer: {
                    Text("Auto-count reads wrist motion on the Watch. It can log reps but never finishes a movement: the rep that moves the sequence on always comes from you.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                }
            }
            .scrollContentBackground(.hidden)
            .senseBackground(.full)
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

/// Font attribution and the full licence text, per OFL clause 2.
struct AcknowledgementsView: View {
    private let attribution = SenseFont.attribution

    var body: some View {
        List {
            Section {
                LabeledContent("Typeface", value: attribution.name)
                LabeledContent("Licence", value: attribution.license)
                Text(attribution.copyright)
                    .font(.footnote)
                    .foregroundStyle(SenseColor.inkSecondary)
                Text(attribution.note)
                    .font(.footnote)
                    .foregroundStyle(SenseColor.inkSecondary)
            } header: {
                Text("Display type")
            }

            Section("Licence text") {
                Text(SenseFont.licenseText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SenseColor.inkSecondary)
                    .textSelection(.enabled)
            }
        }
        .scrollContentBackground(.hidden)
        .senseBackground(.none)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsTabView()
}
