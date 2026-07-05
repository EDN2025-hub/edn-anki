import SwiftUI

/// Pose du verrou d'engagement (façon SelfLock) :
/// - durée choisie (1 jour à 1 an) ;
/// - un code d'urgence aléatoire est généré et affiché UNE SEULE FOIS,
///   à remettre à une personne de confiance (pas à soi-même) ;
/// - avant l'échéance, rien ne peut être désactivé sans ce code.
struct LockSetupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var duration: Duration = .month1
    @State private var generatedCode: String?
    @State private var codeCopied = false

    enum Duration: String, CaseIterable, Identifiable {
        case day1 = "24 heures"
        case week1 = "1 semaine"
        case month1 = "1 mois"
        case month3 = "3 mois"
        case month6 = "6 mois"
        case year1 = "1 an"
        var id: String { rawValue }
        var interval: TimeInterval {
            switch self {
            case .day1: return 86400
            case .week1: return 7 * 86400
            case .month1: return 30 * 86400
            case .month3: return 91 * 86400
            case .month6: return 182 * 86400
            case .year1: return 365 * 86400
            }
        }
    }

    var body: some View {
        NavigationStack {
            if let code = generatedCode {
                codeView(code)
            } else {
                setupView
            }
        }
    }

    private var setupView: some View {
        Form {
            Section("Durée du verrou") {
                Picker("Durée", selection: $duration) {
                    ForEach(Duration.allCases) { d in Text(d.rawValue).tag(d) }
                }
                .pickerStyle(.inline)
            }
            Section {
                Button("Verrouiller maintenant") {
                    let until = Date().addingTimeInterval(duration.interval)
                    generatedCode = state.lock(until: until)
                }
                .font(.headline)
            } footer: {
                Text("Jusqu'à l'échéance : la protection ne peut pas être désactivée, l'app ne peut pas être supprimée et la liste d'apps bloquées ne peut pas être réduite. Un code d'urgence sera affiché une seule fois — confiez-le à quelqu'un d'autre.")
            }
        }
        .navigationTitle("Verrou d'engagement")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
    }

    private func codeView(_ code: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill").font(.system(size: 44)).foregroundStyle(.orange)
            Text("Code d'urgence").font(.title2.bold())
            Text(code)
                .font(.system(.title3, design: .monospaced).bold())
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
                .textSelection(.enabled)
            Text("Ce code ne sera JAMAIS réaffiché. Envoyez-le à une personne de confiance puis supprimez-le de cet appareil. Sans lui, impossible de déverrouiller avant le \(state.lockUntil!.formatted(date: .long, time: .shortened)).")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                UIPasteboard.general.string = code
                codeCopied = true
            } label: {
                Label(codeCopied ? "Copié" : "Copier le code",
                      systemImage: codeCopied ? "checkmark" : "doc.on.doc")
            }
            Button("J'ai transmis le code — terminer") { dismiss() }
                .font(.headline)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .interactiveDismissDisabled()
    }
}
