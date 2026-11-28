import SwiftUI

@main
struct AltRightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // macOS 26 stamps SF Symbol icons onto standard menu rows — a gear
        // on “Settings…”, and an empty icon column on every row that gets
        // none. The app sets no menu images of its own, so the whole feature
        // is switched off for its menus. Set before NSApplication builds any
        // menu; this is the programmatic form of
        //   defaults write <bundle id> NSMenuEnableActionImages -bool NO
        // (macOS 27 has a per-item opt-out as well, see StatusItemController).
        UserDefaults.standard.set(false, forKey: "NSMenuEnableActionImages")
    }

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
