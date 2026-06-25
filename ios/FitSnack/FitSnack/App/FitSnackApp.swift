import SwiftUI

/// App entry point.
///
/// US-A01 wires the minimal app shell: a single window scene showing the
/// placeholder `RootView`. Later stories attach the CoreData persistence
/// controller (US-A04), the ServiceContainer and AppState (US-A05), and the
/// real onboarding/tab routing on top of this shell.
@main
struct FitSnackApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
