import Foundation

/// Extension Safari Content Blocker.
/// Sert la liste mise à jour depuis l'App Group si elle existe (téléchargée
/// par l'app : nouveaux domaines + rotations), sinon la liste embarquée.
final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    private let appGroup = "group.com.example.selfshield"

    func beginRequest(with context: NSExtensionContext) {
        let updated = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("blockerList.json")

        let url: URL
        if let updated, FileManager.default.fileExists(atPath: updated.path) {
            url = updated
        } else {
            url = Bundle.main.url(forResource: "blockerList", withExtension: "json")!
        }

        let item = NSExtensionItem()
        item.attachments = [NSItemProvider(contentsOf: url)!]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
