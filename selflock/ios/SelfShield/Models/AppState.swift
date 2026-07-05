import Foundation
import CryptoKit
import FamilyControls
import Combine

/// État persistant de l'app (App Group, partagé avec l'extension).
final class AppState: ObservableObject {
    static let shared = AppState()
    private let defaults = UserDefaults(suiteName: C.appGroup)!

    // MARK: - Verrou d'engagement (façon SelfLock)

    /// Date jusqu'à laquelle la protection est verrouillée : impossible de
    /// désactiver ou d'assouplir quoi que ce soit avant cette date sans le
    /// code d'urgence (à confier à une personne de confiance).
    @Published var lockUntil: Date? {
        didSet { defaults.set(lockUntil, forKey: "lockUntil") }
    }

    /// SHA-256 du code d'urgence. Le code en clair n'est affiché qu'une
    /// seule fois, à la création du verrou.
    private(set) var unlockCodeHash: String? {
        get { defaults.string(forKey: "unlockCodeHash") }
        set { defaults.set(newValue, forKey: "unlockCodeHash") }
    }

    /// Sélection d'apps à bloquer (Twitter, Reddit, navigateurs tiers…)
    /// via FamilyActivityPicker — les jetons ne peuvent pas être codés en dur.
    @Published var activitySelection = FamilyActivitySelection() {
        didSet { persistSelection() }
    }

    @Published var protectionEnabled: Bool {
        didSet { defaults.set(protectionEnabled, forKey: "protectionEnabled") }
    }

    /// Mode strict : interdit toute installation d'app (anti-VPN).
    /// Peut être ACTIVÉ à tout moment, mais désactivé seulement hors verrou.
    @Published var strictMode: Bool {
        didSet { defaults.set(strictMode, forKey: "strictMode") }
    }

    @Published var lastBlocklistUpdate: Date? {
        didSet { defaults.set(lastBlocklistUpdate, forKey: "lastBlocklistUpdate") }
    }

    var isLocked: Bool {
        guard let until = lockUntil else { return false }
        return Date() < until
    }

    private init() {
        protectionEnabled = defaults.bool(forKey: "protectionEnabled")
        strictMode = defaults.bool(forKey: "strictMode")
        lockUntil = defaults.object(forKey: "lockUntil") as? Date
        lastBlocklistUpdate = defaults.object(forKey: "lastBlocklistUpdate") as? Date
        if let data = defaults.data(forKey: "activitySelection"),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            activitySelection = sel
        }
    }

    private func persistSelection() {
        if let data = try? JSONEncoder().encode(activitySelection) {
            defaults.set(data, forKey: "activitySelection")
        }
    }

    // MARK: - Verrouillage

    /// Crée le verrou et renvoie le code d'urgence EN CLAIR (affiché une
    /// seule fois — à remettre à un tiers de confiance, pas à garder).
    func lock(until date: Date) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<24).map { _ in alphabet.randomElement()! })
        unlockCodeHash = Self.sha256(code)
        lockUntil = date
        return code
    }

    /// Déverrouillage anticipé avec le code d'urgence.
    func unlock(with code: String) -> Bool {
        let normalized = code.uppercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard let hash = unlockCodeHash, Self.sha256(normalized) == hash else {
            return false
        }
        lockUntil = nil
        unlockCodeHash = nil
        return true
    }

    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
