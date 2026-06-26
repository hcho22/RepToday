import SwiftUI

/// App entry point.
///
/// US-A01 wired the minimal app shell; US-A04 attaches the CoreData stack, injecting
/// its main-queue context into the environment so later views can read it. The stack is
/// local-only (no iCloud account required); CloudKit sync lands in US-J02. The
/// ServiceContainer and AppState (US-A05) and the real onboarding/tab routing layer on
/// top of this shell next.
@main
struct FitSnackApp: App {
    /// The app-wide CoreData stack, instantiated at launch so the on-device store loads
    /// immediately. Local-only for now - it never requires an iCloud account.
    private let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
        }
    }
}
