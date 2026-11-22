import SwiftUI

@main
struct AltRightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu-bar icon and its all-in-one panel are owned by
        // `StatusItemController`, because `MenuBarExtra` cannot host a search
        // field. The Settings scene is the real settings window, so ⌘, and the
        // app menu cannot open an empty shell.
        Settings {
            ContentView()
        }
    }
}
