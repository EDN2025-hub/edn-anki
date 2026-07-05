import DeviceActivity
import FamilyControls
import Foundation

/// Extension DeviceActivity : iOS invoque cette classe EN DEHORS de l'app
/// (processus système), au début et à la fin de chaque intervalle surveillé.
/// On en profite pour ré-affirmer toutes les restrictions : même si l'app
/// SelfShield est fermée, purgée de la RAM, ou pas relancée après un
/// redémarrage, la protection est ré-appliquée par le système.
final class SelfShieldMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        reassert()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        reassert()
    }

    private func reassert() {
        let defaults = UserDefaults(suiteName: C.appGroup)!
        guard defaults.bool(forKey: "protectionEnabled") else { return }

        var selection = FamilyActivitySelection()
        if let data = defaults.data(forKey: "activitySelection"),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self,
                                                 from: data) {
            selection = saved
        }
        let strict = defaults.bool(forKey: "strictMode")
        ShieldManager.shared.apply(selection: selection, strictMode: strict)
    }
}
