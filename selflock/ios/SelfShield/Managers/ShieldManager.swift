import Foundation
import FamilyControls
import ManagedSettings

/// Applique les restrictions Screen Time (ManagedSettings).
/// C'est le cœur "non contournable" de l'app :
///  - filtre de contenu adulte SYSTÈME d'Apple (Safari + vues WebKit,
///    navigation privée automatiquement désactivée) ;
///  - blocage de domaines supplémentaires (Twitter/Reddit + racines majeures) ;
///  - interdiction de SUPPRIMER des apps (donc SelfShield lui-même) ;
///  - shield des apps choisies (app Twitter/Reddit natives, navigateurs tiers).
final class ShieldManager {
    static let shared = ShieldManager()
    private let store = ManagedSettingsStore(named: .init("selfshield"))

    /// Autorisation Screen Time (une seule fois).
    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Active toutes les protections.
    func apply(selection: FamilyActivitySelection) {
        // 1. Filtre web système : le filtre "adulte" automatique d'Apple
        //    + nos domaines. S'applique à Safari et à toutes les WebView,
        //    et désactive la navigation privée.
        let extra = Set(C.screenTimeExtraDomains.map { WebDomain(domain: $0) })
        store.webContent.blockedByFilter = .auto(extra, except: [])

        // 2. Anti-contournement : interdit la suppression d'apps.
        //    -> SelfShield ne peut pas être désinstallé tant que la
        //       protection est active.
        store.application.denyAppRemoval = true

        // 3. Shield des apps sélectionnées (Twitter, Reddit, navigateurs
        //    tiers sans content blocker…).
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil : selection.webDomainTokens
    }

    /// Désactive tout (uniquement si le verrou est levé — contrôlé en amont).
    func clear() {
        store.clearAllSettings()
    }
}
