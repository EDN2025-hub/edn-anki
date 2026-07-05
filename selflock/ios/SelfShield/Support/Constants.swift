import Foundation

enum C {
    /// App Group partagé entre l'app et l'extension Safari.
    static let appGroup = "group.com.example.selfshield"

    /// Identifiant du Safari Content Blocker (doit matcher le bundle id
    /// de l'extension généré par XcodeGen : <prefix>.SelfShield.ContentBlocker).
    static let blockerIdentifier = "com.example.selfshield.SelfShield.ContentBlocker"

    /// Tâche de fond de mise à jour de la blocklist.
    static let refreshTaskId = "com.example.selfshield.refreshBlocklist"

    /// Source distante de la blocklist (mise à jour continue : nouveaux
    /// domaines + rotations). Pointez vers votre fork si besoin.
    static let remoteBlocklistURL = URL(
        string: "https://raw.githubusercontent.com/EDN2025-hub/edn-anki/main/selflock/data/blockerList.json"
    )!

    /// Domaines bloqués au niveau Screen Time (filtre système, hors Safari
    /// Apple applique déjà son filtre adulte automatique ; on y ajoute les
    /// plateformes choisies par l'utilisateur et quelques racines majeures).
    /// La liste exhaustive (~milliers de domaines) vit dans le Content
    /// Blocker Safari ; Screen Time est limité à un petit ensemble.
    static let screenTimeExtraDomains: [String] = [
        // Plateformes bloquées par choix explicite de l'utilisateur
        "twitter.com", "x.com", "t.co", "twimg.com",
        "reddit.com", "redd.it", "redditmedia.com", "redditstatic.com",
        // Racines majeures & annuaire
        "theporndude.com", "pornhub.com", "xvideos.com", "xnxx.com",
        "xhamster.com", "redtube.com", "youporn.com", "spankbang.com",
        "onlyfans.com", "fansly.com", "chaturbate.com", "stripchat.com",
        "livejasmin.com", "bongacams.com", "cam4.com", "myfreecams.com",
        "rule34.xxx", "nhentai.net", "e621.net", "f95zone.to",
        "erome.com", "motherless.com", "heavy-r.com", "kaotic.com",
    ]
}
