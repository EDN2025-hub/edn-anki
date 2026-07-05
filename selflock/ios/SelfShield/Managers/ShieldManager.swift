import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

/// Applique les restrictions Screen Time (ManagedSettings).
///
/// PERSISTANCE : ces réglages sont stockés et appliqués par le démon système
/// d'iOS, pas par l'app. Ils restent actifs après un redémarrage de
/// l'iPhone, après la fermeture de l'app (swipe) et quand iOS purge l'app
/// de la RAM. L'app ne sert qu'à les poser/retirer. En complément,
/// l'extension SelfShieldMonitor (DeviceActivity) les ré-affirme chaque
/// jour, même si l'app n'est jamais rouverte.
///
/// Ce fichier est compilé dans l'app ET dans l'extension Monitor.
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
    /// - Parameters:
    ///   - selection: apps/catégories choisies via FamilyActivityPicker.
    ///   - strictMode: interdit TOUTE installation d'app (App Store masqué),
    ///     ce qui neutralise aussi l'installation d'apps VPN/navigateurs
    ///     pour contourner le filtre.
    func apply(selection: FamilyActivitySelection, strictMode: Bool) {
        // ── Web ───────────────────────────────────────────────────────────
        // Filtre adulte SYSTÈME d'Apple + nos domaines. S'applique à Safari
        // et à toutes les WebView, désactive la navigation privée.
        // Ce filtre est appliqué au niveau du moteur WebKit, SUR l'appareil :
        // changer de DNS ou activer un VPN ne le contourne PAS.
        let extra = Set(C.screenTimeExtraDomains.map { WebDomain(domain: $0) })
        store.webContent.blockedByFilter = .auto(extra, except: [])

        // ── App Store ─────────────────────────────────────────────────────
        // Le blocage ciblé des apps (Twitter, Reddit, VPN…) se fait par le
        // shield ci-dessous : les plafonds d'âge sont trop grossiers (12+
        // bloquerait aussi Claude, ChatGPT, Firefox… classées 17+).
        // En mode strict uniquement : App Store limité à 12+ ET plus
        // aucune installation d'app (anti-VPN maximal).
        store.appStore.maximumRating = strictMode ? 300 : nil
        store.application.denyAppInstallation = strictMode

        // ── Anti-contournement ────────────────────────────────────────────
        // Impossible de SUPPRIMER des apps -> SelfShield ne peut pas être
        // désinstallée tant que la protection est active.
        store.application.denyAppRemoval = true
        // Date/heure automatiques imposées : empêche d'avancer l'horloge
        // pour faire expirer le verrou d'engagement.
        store.dateAndTime.requireAutomaticDateAndTime = true
        // Verrouille les comptes (empêche la déconnexion de l'identifiant
        // Apple, autre voie classique de contournement).
        store.account.lockAccounts = true

        // ── Contenus explicites hors web ──────────────────────────────────
        store.media.denyExplicitContent = true      // musique/podcasts explicites
        store.media.denyBookstoreErotica = true     // livres érotiques
        store.media.maximumMovieRating = 400        // films : max R (pas de NC-17)

        // ── Apps sélectionnées (Twitter, Reddit, navigateurs tiers…) ──────
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
        DeviceActivityCenter().stopMonitoring()
    }

    // MARK: - Ré-affirmation par le système (survit à la fermeture de l'app)

    /// Démarre la surveillance DeviceActivity : iOS réveillera l'extension
    /// SelfShieldMonitor à chaque début/fin d'intervalle (quotidien), qui
    /// ré-appliquera les réglages — même si l'app est fermée, purgée de la
    /// RAM ou jamais relancée après un redémarrage.
    func startSystemReassertion() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let center = DeviceActivityCenter()
        do {
            try center.startMonitoring(.init("selfshield.daily"), during: schedule)
        } catch {
            // déjà en cours de surveillance : rien à faire
        }
    }
}
