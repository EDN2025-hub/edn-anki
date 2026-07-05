import SwiftUI

/// Déverrouillage anticipé avec le code d'urgence (détenu par un tiers).
struct UnlockView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code d'urgence", text: $code)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if failed {
                        Text("Code incorrect.").foregroundStyle(.red).font(.footnote)
                    }
                } footer: {
                    Text("Le verrou expire de lui-même le \(state.lockUntil?.formatted(date: .long, time: .shortened) ?? "—"). Le code d'urgence est détenu par votre personne de confiance.")
                }
                Section {
                    Button("Déverrouiller", role: .destructive) {
                        if state.unlock(with: code) {
                            dismiss()
                        } else {
                            failed = true
                        }
                    }
                    .disabled(code.count < 8)
                }
            }
            .navigationTitle("Déverrouillage")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
    }
}
