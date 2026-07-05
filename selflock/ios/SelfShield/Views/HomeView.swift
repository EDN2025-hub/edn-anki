import SwiftUI
import FamilyControls

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var blockerOn = false
    @State private var showLockSetup = false
    @State private var showUnlock = false
    @State private var showPicker = false
    @State private var updating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("Protection active").font(.headline)
                            Text(state.isLocked
                                 ? "Verrouillée jusqu'au \(state.lockUntil!.formatted(date: .abbreviated, time: .shortened))"
                                 : "Non verrouillée — posez un verrou d'engagement")
                                .font(.footnote)
                                .foregroundStyle(state.isLocked ? .secondary : .orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Couches de blocage") {
                    layer("Filtre système Apple + \(C.screenTimeExtraDomains.count) domaines",
                          detail: "Safari & WebView, navigation privée désactivée, Twitter/X et Reddit bloqués",
                          on: true)
                    layer("Bloqueur Safari (base ThePornDude)",
                          detail: blockerOn
                              ? "Actif — liste complète + regex anti-rotation de domaines"
                              : "Inactif : Réglages > Apps > Safari > Extensions",
                          on: blockerOn)
                    layer("Suppression d'apps interdite",
                          detail: "SelfShield ne peut pas être désinstallée",
                          on: true)
                    layer("\(state.activitySelection.applicationTokens.count) app(s) verrouillée(s)",
                          detail: "Apps natives (Twitter, Reddit, navigateurs tiers…)",
                          on: !state.activitySelection.applicationTokens.isEmpty)
                }

                Section("Base de données") {
                    HStack {
                        Text("Dernière mise à jour")
                        Spacer()
                        Text(state.lastBlocklistUpdate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        updating = true
                        Task {
                            await BlocklistUpdater.shared.updateNow()
                            updating = false
                        }
                    } label: {
                        HStack {
                            Text("Mettre à jour maintenant")
                            if updating { Spacer(); ProgressView() }
                        }
                    }
                }

                Section("Réglages") {
                    Button("Modifier les apps bloquées…") { showPicker = true }
                        .disabled(state.isLocked)
                        .familyActivityPicker(isPresented: $showPicker,
                                              selection: $state.activitySelection)

                    if state.isLocked {
                        Button("Déverrouillage d'urgence…", role: .destructive) {
                            showUnlock = true
                        }
                    } else {
                        Button("Poser un verrou d'engagement…") { showLockSetup = true }
                        Button("Désactiver la protection", role: .destructive) {
                            ShieldManager.shared.clear()
                            state.protectionEnabled = false
                        }
                    }
                } footer: {
                    if state.isLocked {
                        Text("Pendant le verrou : impossible de désactiver la protection, de retirer des apps bloquées ou de désinstaller l'app. Le retrait de l'autorisation Temps d'écran est également détecté et ré-appliqué.")
                    }
                }
            }
            .navigationTitle("SelfShield")
            .task { blockerOn = await BlocklistUpdater.shared.blockerEnabled() }
            .onChange(of: state.activitySelection) { _ in
                ShieldManager.shared.apply(selection: state.activitySelection)
            }
            .sheet(isPresented: $showLockSetup) { LockSetupView() }
            .sheet(isPresented: $showUnlock) { UnlockView() }
        }
    }

    private func layer(_ title: String, detail: String, on: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: on ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(on ? .green : .red)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
