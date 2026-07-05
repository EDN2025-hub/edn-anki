import Foundation
import BackgroundTasks
import SafariServices

/// Mise à jour de la blocklist Safari.
///
/// Les sites pornos changent régulièrement de nom de domaine : la liste
/// embarquée contient déjà des regex de rotation (marque + n'importe quel
/// TLD), et cette classe télécharge en plus la dernière version publiée de
/// blockerList.json (pipeline ThePornDude) puis recharge l'extension.
final class BlocklistUpdater {
    static let shared = BlocklistUpdater()

    private var groupListURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: C.appGroup)?
            .appendingPathComponent("blockerList.json")
    }

    // MARK: - Tâche de fond

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: C.refreshTaskId,
                                        using: nil) { task in
            self.handle(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: C.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(task: BGAppRefreshTask) {
        scheduleRefresh()
        let work = Task {
            _ = await self.updateNow()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    // MARK: - Mise à jour

    /// Télécharge la dernière blocklist, la valide, l'installe dans l'App
    /// Group et recharge le Content Blocker. Renvoie true si succès.
    @discardableResult
    func updateNow() async -> Bool {
        do {
            var request = URLRequest(url: C.remoteBlocklistURL)
            request.timeoutInterval = 60
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }

            // Validation stricte : JSON de règles Safari bien formé,
            // uniquement des actions "block" (aucune règle ne peut
            // AUTORISER quoi que ce soit via une mise à jour distante).
            guard let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !rules.isEmpty,
                  rules.allSatisfy({
                      ($0["action"] as? [String: Any])?["type"] as? String == "block"
                          && $0["trigger"] != nil
                  })
            else { return false }

            guard let dest = groupListURL else { return false }
            try data.write(to: dest, options: .atomic)
            try await reloadBlocker()
            await MainActor.run {
                AppState.shared.lastBlocklistUpdate = Date()
            }
            return true
        } catch {
            return false
        }
    }

    func reloadBlocker() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            SFContentBlockerManager.reloadContentBlocker(
                withIdentifier: C.blockerIdentifier) { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }
    }

    /// L'extension est-elle activée dans Réglages > Safari > Extensions ?
    func blockerEnabled() async -> Bool {
        await withCheckedContinuation { cont in
            SFContentBlockerManager.getStateOfContentBlocker(
                withIdentifier: C.blockerIdentifier) { state, _ in
                cont.resume(returning: state?.isEnabled ?? false)
            }
        }
    }
}
