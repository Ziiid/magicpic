import SwiftUI

/// Förval - ett tryck och bilden får bakgrund, form och effekter (se
/// `QuickPreset`). Man kan justera vidare med de vanliga verktygen efteråt,
/// och allt är ETT ångra-steg.
struct QuickPresetsView: View {
    let onSelect: (QuickPreset) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(L("Förval"))
                    .font(.headline)
                Text(L("Ett tryck sätter bakgrund, form och effekter. Du kan justera sedan."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(QuickPreset.all) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: preset.systemImage)
                                    .font(.system(size: 26))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(preset.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button(L("Avbryt")) { onDone() }
            }
        }
        .padding(24)
        .sheetFrame(minWidth: 340, idealWidth: 400, minHeight: 440, idealHeight: 500)
    }
}
