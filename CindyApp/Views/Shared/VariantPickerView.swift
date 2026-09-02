import SwiftUI
import CindyKit

/// Variant/scheme picker reused by the Tracker tab's session setup and by
/// `ManualSessionEntryView`. A single-line label (rather than a multi-line
/// `VStack` per row) keeps this correct under every `pickerStyle` a call site
/// might apply — `.menu`, `.segmented`, `.inline`, `.navigationLink` — since
/// some of those render each option's full label content compactly.
struct VariantPickerView: View {
    @Binding var selection: CindyVariant

    var body: some View {
        Picker("Variant", selection: $selection) {
            ForEach(CindyVariant.allCases) { variant in
                Text("\(variant.displayName) — \(subtitle(for: variant))")
                    .tag(variant)
            }
        }
    }

    private func subtitle(for variant: CindyVariant) -> String {
        let scheme = variant.movementSequence
            .map { "\($0.reps) \($0.movement.displayName)" }
            .joined(separator: " / ")
        let minutes = Int(variant.timeCapSeconds) / 60
        return "\(scheme) · \(minutes):00 cap"
    }
}

private struct VariantPickerPreviewHost: View {
    @State private var variant: CindyVariant = .rx

    var body: some View {
        Form {
            Section("Variant") {
                VariantPickerView(selection: $variant)
            }
        }
    }
}

#Preview {
    VariantPickerPreviewHost()
}
