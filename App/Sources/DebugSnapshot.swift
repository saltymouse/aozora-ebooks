import AppKit
import AozoraKit

/// Development aid: `--snapshot <dir> [--after <seconds>] [files…]` adds the files, waits,
/// then writes every app window (including sheets) to PNG. Needs no screen-recording permission.
@MainActor
enum DebugSnapshot {
	static func runIfRequested(_ model: AppModel) {
		let args = CommandLine.arguments
		guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
		let dir = URL(fileURLWithPath: args[i + 1])
		var delay = 4.0
		if let a = args.firstIndex(of: "--after"), a + 1 < args.count { delay = Double(args[a + 1]) ?? delay }
		let flagValues = Set(["--snapshot", "--dst", "--after", "--settings", "--ini"].compactMap { f in args.firstIndex(of: f).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } })
		let files = args.dropFirst().filter { $0.hasPrefix("/") && !flagValues.contains($0) }.map { URL(fileURLWithPath: $0) }
		let links = args.filter { $0.hasPrefix("http") }.compactMap(URL.init(string:))
		let savedSettings = model.settings, savedPreset = model.presetName
		if let a = args.firstIndex(of: "--ini"), a + 1 < args.count, let data = FileManager.default.contents(atPath: args[a + 1]) {
			model.settings.apply(ini: JavaProperties.parse(data))
		}
		if args.contains("--log") { model.showLog = true }
		let savedConfirm = model.settings.confirm
		let savedSame = model.settings.samePath, savedDst = model.settings.dstPath
		if let d = args.firstIndex(of: "--dst"), d + 1 < args.count {
			model.settings.samePath = false
			model.settings.dstPath = args[d + 1]
		}
		if args.contains("--no-review") { model.settings.confirm = false }
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.add(urls: files + links) }
		if let t = args.firstIndex(of: "--settings"), t + 1 < args.count, let tab = Int(args[t + 1]) {
			UserDefaults.standard.set(tab, forKey: "settingsTab")
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				if let appMenu = NSApp.mainMenu?.items.first?.submenu,
				   let item = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
					appMenu.performActionForItem(at: appMenu.index(of: item))
				}
			}
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
			try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			for (n, window) in NSApp.windows.enumerated() where window.isVisible {
				guard let view = window.contentView else { continue }
				guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
				view.cacheDisplay(in: view.bounds, to: rep)
				let name = window.isSheet ? "sheet" : "window"
				try? "\(window.frame) min \(window.minSize) content \(window.contentMinSize)".write(to: dir.appendingPathComponent("\(n)-frame.txt"), atomically: true, encoding: .utf8)
				try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(n)-\(name).png"))
			}
			model.settings.confirm = savedConfirm
			model.settings.samePath = savedSame
			model.settings.dstPath = savedDst
			if args.contains("--ini") {
				model.settings = savedSettings
				model.presetName = savedPreset
			}
			if args.contains("--quit") { exit(0) }
		}
	}
}
