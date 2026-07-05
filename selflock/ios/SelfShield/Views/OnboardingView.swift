import SwiftUI
import FamilyControls

/// Mise en route : autorisation Screen Time, activation du Content Blocker
/// Safari, sélection des apps à bloquer, puis activation.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var authorized = ShieldManager.shared.isAuthorized
    @State private var blockerOn = false
    @State private var authError: String?
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SelfShield").font(.largeTitle.bold())
                        Text("Bloque les sites pornographiques et NSFW (dont Twitter/X et Reddit) sur tout l'appareil, et se verrouille pour ne pas être contourné.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Étape 1 — Temps d'écran") {
                    stepRow(done: authorized,
                            title: "Autoriser le contrôle Temps d'écran",
                            detail: "Active le filtre adulte système d'Apple, bloque Twitter/Reddit et empêche la suppression de l'app.")
                    if !authorized {
                        Button("Autoriser…") {
                            Task {
                                do {
                                    try await ShieldManager.shared.requestAuthorization()
                                    authorized = ShieldManager.shared.isAuthorized
                                } catch {
                                    authError = error.localizedDescription
                                }
                            }
                        }
                        if let authError {
                            Text(authError).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }

                Section("Étape 2 — Safari") {
                    stepRow(done: blockerOn,
                            title: "Activer le bloqueur de contenu",
                            detail: "Réglages > Apps > Safari > Extensions > SelfShield Blocker : Activer. C'est la liste complète ThePornDude (~milliers de sites).")
                    Button("Vérifier l'activation") {
                        Task { blockerOn = await BlocklistUpdater.shared.blockerEnabled() }
                    }
                }

                Section("Étape 3 — Apps à bloquer (optionnel)") {
                    Text("Sélectionnez les apps natives à verrouiller : Twitter/X, Reddit, et les navigateurs alternatifs (Chrome, Firefox…) qui n'appliquent pas le bloqueur Safari.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Choisir les apps…") { showPicker = true }
                        .familyActivityPicker(isPresented: $showPicker,
                                              selection: $state.activitySelection)
                    if !state.activitySelection.applicationTokens.isEmpty {
                        Text("\(state.activitySelection.applicationTokens.count) app(s) sélectionnée(s)")
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        ShieldManager.shared.apply(selection: state.activitySelection,
                                                   strictMode: state.strictMode)
                        ShieldManager.shared.startSystemReassertion()
                        state.protectionEnabled = true
                        Task { await BlocklistUpdater.shared.updateNow() }
                    } label: {
                        Text("Activer la protection")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .disabled(!authorized)
                } footer: {
                    Text("Après activation, vous pourrez poser un verrou d'engagement pour rendre la protection irrévocable pendant la durée choisie.")
                }
            }
            .navigationTitle("Mise en route")
            .task { blockerOn = await BlocklistUpdater.shared.blockerEnabled() }
        }
    }

    private func stepRow(done: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
