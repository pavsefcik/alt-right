import SwiftUI

@main
struct AltRightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Alt Right", systemImage: "cursorarrow.click.2") {
            MenuBarView()
        }
    }
}
