import SwiftUI
import AozoraKit
import UniformTypeIdentifiers

/// The main window: drop things in, books appear on the shelf.
struct ShelfView: View {
	@Environment(AppModel.self) private var model
	@State private var dropTargeted = false
	@State private var linkText = ""
	@State private var shelfWidth: CGFloat = 800
	@State private var selected: BookJob.ID?
	@FocusState private var linkFocused: Bool

	var body: some View {
		@Bindable var model = model
		VStack(spacing: 0) {
			ZStack {
				PaperBackground()
				if model.jobs.isEmpty {
					DropZone(targeted: dropTargeted, chooseFiles: chooseFiles, pasteLink: { linkFocused = true })
						.padding(40)
						.transition(.opacity.combined(with: .scale(scale: 0.96)))
				} else {
					shelf
				}
				if dropTargeted && !model.jobs.isEmpty {
					RoundedRectangle(cornerRadius: 18)
						.strokeBorder(Washi.vermilion.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
						.padding(10)
						.allowsHitTesting(false)
						.transition(.opacity)
				}
			}
			.animation(.spring(response: 0.35), value: model.jobs.isEmpty)
			.animation(.easeOut(duration: 0.15), value: dropTargeted)
			.dropDestination(for: DroppedItem.self) { items, _ in
				accept(items)
				return true
			} isTargeted: { dropTargeted = $0 }

			BottomBar(linkText: $linkText, linkFocused: $linkFocused, chooseFiles: chooseFiles)
		}
		.frame(minWidth: 640, minHeight: 460)
		.toolbar { ShelfToolbar() }
		.navigationTitle("Aozora Ebooks")
		.navigationSubtitle("Makes \(DevicePreset.describe(ext: model.settings.ext))")
		.sheet(item: $model.reviewing) { job in
			ReviewSheet(job: job)
		}
		.inspector(isPresented: $model.showLog) {
			LogView(job: model.jobs.first { $0.id == selected })
				.inspectorColumnWidth(min: 280, ideal: 340, max: 520)
		}
		.alert("This preset makes .mobi files", isPresented: $model.askKindlegen) {
			Button("Make EPUB Instead") { model.answerKindlegen(useEpub: true) }
			Button("Don't Convert", role: .cancel) { model.answerKindlegen(useEpub: false) }
		} message: {
			Text(".mobi needs Amazon's kindlegen, which isn't installed (it comes with Kindle Previewer). Kindle reads EPUB too: send it with Send to Kindle. The preset's screen and layout settings are kept.")
		}
		.alert("Hmm", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
			Button("OK") { model.alert = nil }
		} message: {
			Text(model.alert ?? "")
		}
		.onPasteCommand(of: [.fileURL, .url, .plainText]) { _ in
			accept(DroppedItem.fromPasteboard())
		}
	}

	private var shelf: some View {
		let columns = max(1, Int((shelfWidth - 48) / 168))
		let rows = stride(from: 0, to: model.jobs.count, by: columns).map { Array(model.jobs[$0..<min($0 + columns, model.jobs.count)]) }
		return ScrollView {
			VStack(spacing: 34) {
				ForEach(rows.indices, id: \.self) { r in
					VStack(spacing: 0) {
						HStack(alignment: .bottom, spacing: 28) {
							ForEach(rows[r]) { job in
								BookCard(job: job, selected: selected == job.id)
									.onTapGesture { selected = job.id }
									.transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .scale.combined(with: .opacity)))
							}
							Spacer(minLength: 0)
						}
						.padding(.horizontal, 32)
						ShelfLedge()
					}
				}
			}
			.padding(.vertical, 28)
		}
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shelfWidth = $0 }
		.contentShape(Rectangle())
		.onTapGesture { selected = nil }
	}

	private func chooseFiles() {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = true
		panel.canChooseDirectories = true
		panel.allowedContentTypes = [.plainText, .zip, UTType(filenameExtension: "rar") ?? .data, UTType(filenameExtension: "cbz") ?? .zip,
		                             UTType(filenameExtension: "txtz") ?? .zip, .internetShortcut]
		panel.message = String(localized: "Choose Aozora Bunko texts, archives or folders")
		if panel.runModal() == .OK { model.add(urls: panel.urls) }
	}

	private func accept(_ items: [DroppedItem]) {
		for item in items {
			switch item {
			case .url(let url): model.add(urls: [url])
			case .text(let text): model.add(text: text)
			}
		}
	}
}

/// What can land on the shelf: files, links, or text containing links.
enum DroppedItem: Transferable {
	case url(URL)
	case text(String)

	static var transferRepresentation: some TransferRepresentation {
		ProxyRepresentation { (url: URL) in DroppedItem.url(url) }
		ProxyRepresentation { (text: String) in DroppedItem.text(text) }
	}

	/// Files, links or text on the general pasteboard.
	static func fromPasteboard() -> [DroppedItem] {
		let pb = NSPasteboard.general
		if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty { return urls.map { .url($0) } }
		if let text = pb.string(forType: .string) { return [.text(text)] }
		return []
	}
}

/// The wooden ledge each row of books stands on.
struct ShelfLedge: View {
	var body: some View {
		ZStack(alignment: .top) {
			LinearGradient(colors: [Washi.shelf.opacity(0.95), Washi.shelf.opacity(0.75)], startPoint: .top, endPoint: .bottom)
				.frame(height: 12)
			Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
		}
		.clipShape(RoundedRectangle(cornerRadius: 2))
		.shadow(color: .black.opacity(0.25), radius: 4, y: 4)
		.padding(.horizontal, 18)
	}
}

/// First-run invitation to drop files.
struct DropZone: View {
	var targeted: Bool
	var chooseFiles: () -> Void
	var pasteLink: () -> Void

	var body: some View {
		VStack(spacing: 18) {
			Image(systemName: "books.vertical.fill")
				.font(.system(size: 64))
				.foregroundStyle(Washi.vermilion.gradient)
				.symbolEffect(.bounce, value: targeted)
			VStack(spacing: 6) {
				Text("Drop a book here")
					.font(.system(.largeTitle, design: .serif).weight(.semibold))
				Text("Aozora Bunko text (.txt, .zip), comics (.cbz, .rar), or a web novel link from Syosetu, Kakuyomu and friends.")
					.font(.title3)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 460)
			}
			HStack(spacing: 12) {
				Button(action: chooseFiles) { Label("Choose Files…", systemImage: "folder") }
					.controlSize(.large)
					.buttonStyle(.borderedProminent)
					.tint(Washi.vermilion)
				Button(action: pasteLink) { Label("Paste a Link", systemImage: "link") }
					.controlSize(.large)
			}
		}
		.padding(48)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background {
			RoundedRectangle(cornerRadius: 26)
				.strokeBorder(targeted ? Washi.vermilion : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: targeted ? 3 : 2, dash: [12, 8]))
				.background(RoundedRectangle(cornerRadius: 26).fill(.background.opacity(targeted ? 0.55 : 0.3)))
		}
		.scaleEffect(targeted ? 1.015 : 1)
		.animation(.spring(response: 0.3, dampingFraction: 0.6), value: targeted)
	}
}

/// Link field, add button and output location.
struct BottomBar: View {
	@Environment(AppModel.self) private var model
	@Binding var linkText: String
	var linkFocused: FocusState<Bool>.Binding
	var chooseFiles: () -> Void

	var body: some View {
		@Bindable var model = model
		HStack(spacing: 12) {
			HStack(spacing: 6) {
				Image(systemName: "link").foregroundStyle(.secondary)
				TextField("Paste a web novel or Aozora Bunko link", text: $linkText)
					.textFieldStyle(.plain)
					.focused(linkFocused)
					.onSubmit(addLink)
				if !linkText.isEmpty {
					Button("Add", action: addLink).buttonStyle(.borderless).keyboardShortcut(.defaultAction)
				}
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 7)
			.background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

			OutputMenu()

			if model.jobs.contains(where: { $0.phase.isFinished }) {
				Button("Clear Done") { model.clearFinished() }
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.background(.bar)
	}

	private func addLink() {
		let text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return }
		model.add(text: text)
		linkText = ""
	}
}

/// Where EPUBs are saved.
struct OutputMenu: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		Menu {
			Button {
				model.settings.samePath = true
			} label: {
				Label("Next to the Original", systemImage: model.settings.samePath ? "checkmark" : "")
			}
			Button("Choose Folder…") {
				let panel = NSOpenPanel()
				panel.canChooseDirectories = true
				panel.canChooseFiles = false
				panel.canCreateDirectories = true
				panel.prompt = String(localized: "Save Here")
				if panel.runModal() == .OK, let url = panel.url {
					model.settings.dstPath = url.path
					model.settings.samePath = false
				}
			}
			if !model.settings.dstPath.isEmpty {
				Divider()
				Button {
					model.settings.samePath = false
				} label: {
					Label((model.settings.dstPath as NSString).abbreviatingWithTildeInPath, systemImage: model.settings.samePath ? "folder" : "checkmark")
				}
				Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: model.settings.dstPath)) }
			}
		} label: {
			Label(model.settings.samePath || model.settings.dstPath.isEmpty ? String(localized: "Next to original") : (model.settings.dstPath as NSString).lastPathComponent,
			      systemImage: "tray.and.arrow.down")
		}
		.menuStyle(.borderlessButton)
		.fixedSize()
		.help("Where finished books are saved")
	}
}

/// Device preset, writing direction, add and log.
struct ShelfToolbar: ToolbarContent {
	@Environment(AppModel.self) private var model

	var body: some ToolbarContent {
		@Bindable var model = model
		ToolbarItem(placement: .navigation) {
			DeviceMenu()
		}
		ToolbarItem {
			DirectionToggle(vertical: $model.settings.vertical)
		}
		ToolbarItem {
			Toggle(isOn: $model.settings.confirm) {
				Label("Review Before Converting", systemImage: "eye")
			}
			.help("Check the title, cover and table of contents before each book")
		}
		ToolbarItem {
			Button {
				model.showLog.toggle()
			} label: {
				Label("Activity", systemImage: "text.alignleft")
			}
			.help("Show conversion notes and warnings")
		}
	}
}

/// "Make it for…" device picker built from the presets, labelled with what each produces.
struct DeviceMenu: View {
	@Environment(AppModel.self) private var model
	private let hasKindlegen = KindleGen.locate() != nil

	var body: some View {
		Menu {
			Section("Devices") {
				ForEach(model.presets.filter { !$0.isClassic }) { preset in
					presetButton(preset)
				}
			}
			Section("Classic (AozoraEpub3 presets)") {
				ForEach(model.presets.filter(\.isClassic)) { preset in
					presetButton(preset)
				}
			}
			if !model.profiles.isEmpty {
				Section("My Profiles") {
					ForEach(model.profiles) { profile in
						Button {
							model.apply(profile)
						} label: {
							Text(profile.name)
							Text(DevicePreset.describe(ext: profile.ini["Ext"] ?? ".epub"))
						}
					}
				}
			}
			Divider()
			SettingsLink { Text("Fine-Tune Settings…") }
		} label: {
			Label(title, systemImage: Self.symbol(model.currentPreset?.icon))
				.labelStyle(.titleAndIcon)
		}
		.help("Choose the reader you'll read on: screen size, file type and layout follow")
	}

	/// "Kobo Clara → Kobo EPUB"
	private var title: String {
		"\(model.currentPreset?.name ?? String(localized: "Custom")) → \(DevicePreset.describe(ext: model.settings.ext))"
	}

	private func presetButton(_ preset: DevicePreset) -> some View {
		Button {
			model.apply(preset)
		} label: {
			Label {
				Text(preset.name)
				Text(subtitle(preset))
			} icon: {
				Image(systemName: model.presetName == preset.name ? "checkmark" : Self.symbol(preset.icon))
			}
		}
	}

	private func subtitle(_ p: DevicePreset) -> String {
		var parts = [p.needsKindlegen ? (hasKindlegen ? String(localized: "MOBI via kindlegen") : String(localized: "MOBI: needs kindlegen (not installed)")) : p.output]
		if !p.screenSize.isEmpty { parts.append(p.screenSize) }
		return parts.joined(separator: " · ")
	}

	static func symbol(_ icon: String?) -> String {
		switch icon {
		case "kindle", "kobo", "reader": return "rectangle.portrait"
		case "books": return "book"
		default: return "slider.horizontal.3"
		}
	}
}

/// 縦書き / 横書き switch: a small page that turns its lines.
struct DirectionToggle: View {
	@Binding var vertical: Bool

	var body: some View {
		Button {
			withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { vertical.toggle() }
		} label: {
			HStack(spacing: 6) {
				ZStack {
					RoundedRectangle(cornerRadius: 2).stroke(.secondary, lineWidth: 1.2).frame(width: 13, height: 17)
					VStack(spacing: 2.5) {
						ForEach(0..<3, id: \.self) { _ in Capsule().frame(width: 8, height: 1.5) }
					}
					.rotationEffect(.degrees(vertical ? 90 : 0))
				}
				Text(vertical ? "縦書き" : "横書き")
					.font(.system(size: 13, weight: .medium))
					.contentTransition(.numericText())
			}
		}
		.help(vertical ? Text("Vertical text (tategaki). Click for horizontal.") : Text("Horizontal text (yokogaki). Click for vertical."))
		.accessibilityLabel(vertical ? Text("Vertical text") : Text("Horizontal text"))
	}
}
