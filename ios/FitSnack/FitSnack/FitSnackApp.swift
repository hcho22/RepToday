import SwiftUI
import SwiftData

@main
struct FitSnackApp: App {
    @State private var appState = AppState()
    @State private var services: ServiceContainer?

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer.fitSnackContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboarded {
                    MainTabView(appState: appState)
                } else {
                    OnboardingContainerView(appState: appState)
                }
            }
            .environment(\.services, services)
            .task {
                if services == nil {
                    let context = modelContainer.mainContext
                    services = ServiceContainer.mock(modelContext: context)
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
