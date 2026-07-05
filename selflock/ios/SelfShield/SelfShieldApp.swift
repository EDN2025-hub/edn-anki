import SwiftUI

@main
struct SelfShieldApp: App {
    @StateObject private var state = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BlocklistUpdater.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        // Ré-applique systématiquement les protections au
                        // premier plan : si quelque chose a été altéré,
                        // c'est restauré ici.
                        if state.protectionEnabled, ShieldManager.shared.isAuthorized {
                            ShieldManager.shared.apply(selection: state.activitySelection,
                                                       strictMode: state.strictMode)
                            ShieldManager.shared.startSystemReassertion()
                        }
                    } else if phase == .background {
                        BlocklistUpdater.shared.scheduleRefresh()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.protectionEnabled {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}
