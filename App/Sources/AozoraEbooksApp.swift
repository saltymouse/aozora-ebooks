import SwiftUI
import AozoraKit

@main
struct AozoraEbooksApp: App {
	@NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

	var body: some Scene {
		Window("Aozora Ebooks", id: "shelf") {
			ShelfView()
				.environment(appDelegate.model)
				.fontDesign(.rounded)
		}
		.defaultSize(width: 940, height: 660)
		.windowResizability(.contentMinSize)
		.commands {
			CommandGroup(replacing: .newItem) {
				Button("Add Files…") { appDelegate.chooseFiles() }
					.keyboardShortcut("o")
			}
			CommandGroup(after: .pasteboard) {
				Button("Clear Finished Books") { appDelegate.model.clearFinished() }
					.keyboardShortcut(.delete, modifiers: [.command, .shift])
				Button("Stop All") { appDelegate.model.cancelAll() }
					.keyboardShortcut(".")
			}
			CommandGroup(after: .sidebar) {
				Button("Show Activity") { appDelegate.model.showLog.toggle() }
					.keyboardShortcut("l")
			}
		}

		Settings {
			SettingsView()
				.environment(appDelegate.model)
		}
	}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	let model = AppModel()

	/// Files opened from Finder or dropped on the Dock icon.
	func application(_ application: NSApplication, open urls: [URL]) {
		model.add(urls: urls)
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

	func applicationDidFinishLaunching(_ notification: Notification) {
		DebugSnapshot.runIfRequested(model)
	}

	func chooseFiles() {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = true
		panel.canChooseDirectories = true
		if panel.runModal() == .OK { model.add(urls: panel.urls) }
	}
}
