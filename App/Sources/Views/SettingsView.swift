import SwiftUI
import AozoraKit
import UniformTypeIdentifiers

/// Every AozoraEpub3 option, grouped and explained.
struct SettingsView: View {
	@AppStorage("settingsTab") private var tab = 0

	var body: some View {
		TabView(selection: $tab) {
			GeneralPane().tabItem { Label("General", systemImage: "gearshape") }.tag(0)
			BookPane().tabItem { Label("Book", systemImage: "book.closed") }.tag(1)
			TextPane().tabItem { Label("Text", systemImage: "character.ja") }.tag(2)
			ContentsPane().tabItem { Label("Contents", systemImage: "list.bullet.indent") }.tag(3)
			ImagesPane().tabItem { Label("Images", systemImage: "photo") }.tag(4)
			StylePane().tabItem { Label("Style", systemImage: "textformat.size") }.tag(5)
			WebPane().tabItem { Label("Web", systemImage: "globe") }.tag(6)
			ProfilesPane().tabItem { Label("Profiles", systemImage: "person.crop.rectangle.stack") }.tag(7)
		}
		.frame(width: 620, height: 560)
	}
}

// MARK: - Helpers

struct IntField: View {
	let title: LocalizedStringKey
	@Binding var value: Int
	var suffix: LocalizedStringKey?
	var width: CGFloat = 70

	var body: some View {
		LabeledContent(title) {
			HStack(spacing: 4) {
				TextField(title, value: $value, format: .number.grouping(.never))
					.labelsHidden()
					.multilineTextAlignment(.trailing)
					.frame(width: width)
				if let suffix { Text(suffix).foregroundStyle(.secondary) }
			}
		}
	}
}

struct FloatField: View {
	let title: LocalizedStringKey
	@Binding var value: Float
	var suffix: LocalizedStringKey?

	var body: some View {
		LabeledContent(title) {
			HStack(spacing: 4) {
				TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
					.labelsHidden()
					.multilineTextAlignment(.trailing)
					.frame(width: 70)
				if let suffix { Text(suffix).foregroundStyle(.secondary) }
			}
		}
	}
}

struct SizeField: View {
	let title: LocalizedStringKey
	@Binding var width: Int
	@Binding var height: Int

	var body: some View {
		LabeledContent(title) {
			HStack(spacing: 4) {
				TextField("Width", value: $width, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 64)
				Text("×").foregroundStyle(.secondary)
				TextField("Height", value: $height, format: .number.grouping(.never)).frame(width: 64)
				Text("px").foregroundStyle(.secondary)
			}
			.labelsHidden()
		}
	}
}

/// Settings panes edit the shared model; changing anything means the preset no longer applies as-is.
private struct Pane<Content: View>: View {
	@ViewBuilder var content: Content
	var body: some View {
		Form { content }
			.formStyle(.grouped)
	}
}

// MARK: - General

struct GeneralPane: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		Pane {
			Section("Saving") {
				Picker("Save books", selection: $model.settings.samePath) {
					Text("Next to the original file").tag(true)
					Text("In a folder").tag(false)
				}
				if !model.settings.samePath {
					LabeledContent("Folder") {
						HStack {
							Text(model.settings.dstPath.isEmpty ? String(localized: "None chosen") : (model.settings.dstPath as NSString).abbreviatingWithTildeInPath)
								.lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
							Button("Choose…") {
								let panel = NSOpenPanel()
								panel.canChooseDirectories = true
								panel.canChooseFiles = false
								panel.canCreateDirectories = true
								if panel.runModal() == .OK, let url = panel.url { model.settings.dstPath = url.path }
							}
						}
					}
				}
				Toggle("Name files after the book: “[Author] Title.epub”", isOn: $model.settings.autoFileName)
				Toggle("Replace files that already exist", isOn: $model.settings.overWrite)
				Picker("File type", selection: $model.settings.ext) {
					Text(".epub").tag(".epub")
					Text(".kepub.epub (Kobo)").tag(".kepub.epub")
					Text(".fxl.kepub.epub (Kobo fixed layout)").tag(".fxl.kepub.epub")
					Text(".mobi (needs kindlegen)").tag(".mobi")
					Text(".mobi + .epub (needs kindlegen)").tag(".mobi+.epub")
				}
				if model.settings.ext.hasPrefix(".mobi") {
					Text(KindleGen.locate() == nil
						? "kindlegen wasn't found. Install Kindle Previewer, or use .epub: Send to Kindle accepts EPUB files."
						: "kindlegen found. Note Amazon now prefers EPUB via Send to Kindle.")
						.font(.caption).foregroundStyle(.secondary)
				}
			}
			Section("Reading the text") {
				Picker("Text encoding", selection: $model.settings.encoding) {
					Text("Shift_JIS (Aozora Bunko standard)").tag(TextEncoding.shiftJIS)
					Text("UTF-8").tag(TextEncoding.utf8)
				}
				Toggle("Review title, cover and contents before converting", isOn: $model.settings.confirm)
				Toggle("Remember the cover chosen for each file", isOn: $model.settings.coverHistory)
			}
			Section("App") {
				Picker("Language", selection: $language) {
					Text("Same as macOS").tag("")
					Text(verbatim: "日本語").tag("ja")
					Text(verbatim: "English").tag("en")
				}
				.onChange(of: language) { _, lang in
					if lang.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
					else { UserDefaults.standard.set([lang], forKey: "AppleLanguages") }
				}
				if language != initialLanguage {
					Text("The new language shows the next time the app opens.").font(.caption).foregroundStyle(.secondary)
				}
			}
		}
	}

	/// The app's own language override (empty = follow macOS), as set in System Settings or here.
	private static var languageOverride: String {
		(UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first.map { String($0.prefix(2)) } ?? ""
	}
	@State private var language = Self.languageOverride
	private let initialLanguage = Self.languageOverride
}

// MARK: - Book

struct BookPane: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		Pane {
			Section("Title and author") {
				Picker("Opening lines of the text", selection: $model.settings.titleType) {
					ForEach(TitleType.allCases, id: \.self) { Text($0.displayName).tag($0) }
				}
				Toggle("The first line is the publisher", isOn: $model.settings.pubFirst)
				Toggle("Prefer “[Author] Title” from the file name", isOn: $model.settings.useFileName)
			}
			Section("Cover") {
				Picker("Cover image", selection: coverKind) {
					Text("First illustration").tag(0)
					Text("Image with the same name as the text").tag(1)
					Text("No cover").tag(2)
					Text("A specific image…").tag(3)
				}
				if case .firstIllustration = model.settings.cover {
					IntField(title: "Only if it appears within", value: $model.settings.maxCoverLine, suffix: "lines (0 = anywhere)")
				}
				if case .file(let path) = model.settings.cover {
					LabeledContent("Image") { Text((path as NSString).lastPathComponent).foregroundStyle(.secondary) }
				}
				SizeField(title: "Cover size", width: $model.settings.coverW, height: $model.settings.coverH)
			}
			Section("Pages") {
				Toggle("Cover page", isOn: $model.settings.coverPage)
				Toggle("Title page", isOn: $model.settings.titlePageWrite)
				if model.settings.titlePageWrite {
					Picker("Title page style", selection: $model.settings.titlePage) {
						Text("Within the text").tag(TitlePageType.normal)
						Text("Centered page").tag(TitlePageType.middle)
						Text("Horizontal page").tag(TitlePageType.horizontal)
					}
				}
				Toggle("Table of contents page", isOn: $model.settings.tocPage)
				if model.settings.tocPage {
					Picker("Contents page direction", selection: $model.settings.tocVertical) {
						Text("Vertical").tag(true)
						Text("Horizontal").tag(false)
					}
					.pickerStyle(.segmented)
				}
				Picker("Writing direction", selection: $model.settings.vertical) {
					Text("Vertical 縦書き").tag(true)
					Text("Horizontal 横書き").tag(false)
				}
				.pickerStyle(.segmented)
			}
		}
	}

	private var coverKind: Binding<Int> {
		Binding {
			switch model.settings.cover {
			case .firstIllustration: return 0
			case .sameNameImage: return 1
			case .none: return 2
			case .file: return 3
			}
		} set: { v in
			switch v {
			case 0: model.settings.cover = .firstIllustration
			case 1: model.settings.cover = .sameNameImage
			case 2: model.settings.cover = .none
			default:
				let panel = NSOpenPanel()
				panel.allowedContentTypes = [.png, .jpeg, .gif]
				if panel.runModal() == .OK, let url = panel.url { model.settings.cover = .file(url.path) }
			}
		}
	}
}

// MARK: - Text

struct TextPane: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		Pane {
			Section("Upright digits in vertical text (縦中横)") {
				Toggle("Set 2-digit numbers and !? upright", isOn: $model.settings.autoYoko)
				Toggle("…also single digits", isOn: $model.settings.autoYokoNum1).disabled(!model.settings.autoYoko)
				Toggle("…also 3-digit numbers", isOn: $model.settings.autoYokoNum3).disabled(!model.settings.autoYoko)
				Toggle("…also a single ! or ?", isOn: $model.settings.autoYokoEQ1).disabled(!model.settings.autoYoko)
			}
			Section("Spacing") {
				Picker("Full-width spaces at line ends", selection: $model.settings.spaceHyphenation) {
					Text("Leave as is").tag(0)
					Text("Hide (Kobo, Kindle)").tag(1)
					Text("Push to next line (Sony Reader)").tag(2)
				}
				Toggle("Indent paragraphs that don't start with a bracket", isOn: $model.settings.forceIndent)
				Picker("Shorten runs of empty lines by", selection: $model.settings.removeEmptyLine) {
					ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
				}
				Picker("At most", selection: $model.settings.maxEmptyLine) {
					Text("No limit").tag(0)
					ForEach(1...10, id: \.self) { Text("\($0) empty lines").tag($0) }
				}
			}
			Section("Annotations") {
				Picker("［＃「○○」に「××」の注記］", selection: $model.settings.chukiRuby) {
					Text("Hide").tag(0)
					Text("Show as ruby").tag(1)
					Text("Show as small text").tag(2)
				}
				Toggle("Include comment blocks (between ----- lines)", isOn: $model.settings.commentPrint)
				Toggle("Convert annotations inside comments", isOn: $model.settings.commentConvert).disabled(!model.settings.commentPrint)
				Toggle("Add bookmark IDs to every line (Kobo)", isOn: $model.settings.markId)
			}
			Section("Characters") {
				Picker("Kana with combining (han)dakuten", selection: $model.settings.dakutenType) {
					Text("Leave as is").tag(0)
					Text("Overlay the mark").tag(1)
					Text("Use glyph fonts").tag(2)
				}
				Toggle("Keep variation selectors for symbols (U+FE00–FE0E)", isOn: $model.settings.ivsBMP)
				Toggle("Keep variation selectors for kanji (U+E0100–E01EF)", isOn: $model.settings.ivsSSP)
				Text("Kobo and Kindle don't support variation selectors.").font(.caption).foregroundStyle(.secondary)
			}
			Section("Splitting into files") {
				Toggle("Split long sections", isOn: $model.settings.pageBreak)
				if model.settings.pageBreak {
					IntField(title: "Split after", value: $model.settings.pageBreakSize, suffix: "KB")
					Toggle("Split at empty lines", isOn: $model.settings.pageBreakEmpty)
					if model.settings.pageBreakEmpty {
						Picker("At least", selection: $model.settings.pageBreakEmptyLine) {
							ForEach(1...9, id: \.self) { Text("\($0) empty lines").tag($0) }
						}
						IntField(title: "Once a section passes", value: $model.settings.pageBreakEmptySize, suffix: "KB")
					}
					Toggle("Split before headings", isOn: $model.settings.pageBreakChapter)
					if model.settings.pageBreakChapter {
						IntField(title: "Once a section passes", value: $model.settings.pageBreakChapterSize, suffix: "KB")
					}
				}
			}
		}
	}
}

// MARK: - Contents

struct ContentsPane: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		Pane {
			Section("Table of contents") {
				IntField(title: "Longest heading", value: $model.settings.maxChapterNameLength, suffix: "characters")
				Toggle("Include the cover", isOn: $model.settings.coverPageToc)
				Toggle("Include the title", isOn: $model.settings.titleToc)
				Toggle("Join a heading with the line after it", isOn: $model.settings.chapterUseNextLine)
				Toggle("Skip runs of headings (a contents list inside the text)", isOn: $model.settings.chapterExclude)
				Toggle("Nest the contents page", isOn: $model.settings.navNest)
				Toggle("Nest the reader's contents menu (toc.ncx)", isOn: $model.settings.ncxNest)
			}
			Section("Find headings from") {
				Toggle("The first line after a page break", isOn: $model.settings.chapterSection)
				Toggle("［＃見出し］", isOn: $model.settings.chapterH)
				Toggle("［＃大見出し］", isOn: $model.settings.chapterH1)
				Toggle("［＃中見出し］", isOn: $model.settings.chapterH2)
				Toggle("［＃小見出し］", isOn: $model.settings.chapterH3)
				Toggle("…including same-line headings (同行見出し)", isOn: $model.settings.sameLineChapter)
				Toggle("Chapter names: 第〜章, その〜, 序, プロローグ…", isOn: $model.settings.chapterName)
				Toggle("Lines that are just a number", isOn: $model.settings.chapterNumOnly)
				Toggle("A number followed by a heading", isOn: $model.settings.chapterNumTitle)
				Toggle("A number in brackets （一）〈二〉【三】", isOn: $model.settings.chapterNumParen)
				Toggle("A bracketed number followed by a heading", isOn: $model.settings.chapterNumParenTitle)
				Toggle("Lines matching a pattern", isOn: $model.settings.chapterPattern)
				if model.settings.chapterPattern {
					LabeledContent("Regular expression") {
						HStack {
							TextField("Pattern", text: $model.settings.chapterPatternText).font(.body.monospaced())
							Menu("Examples") {
								ForEach(ConversionSettings.chapterPatternExamples, id: \.self) { p in
									Button(p) { model.settings.chapterPatternText = p }
								}
							}
							.fixedSize()
						}
					}
				}
			}
		}
	}
}

// MARK: - Images

struct ImagesPane: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		Pane {
			Section("Screen") {
				SizeField(title: "Reader screen", width: $model.settings.dispW, height: $model.settings.dispH)
				Toggle("Leave out illustrations (keep the cover and gaiji images)", isOn: $model.settings.noIllust)
			}
			Section("Placement") {
				Toggle("Scale images relative to the screen", isOn: $model.settings.imageScaleChecked)
				if model.settings.imageScaleChecked {
					FloatField(title: "Scale", value: $model.settings.imageScale, suffix: "×")
				}
				Toggle("Let text wrap around small images", isOn: $model.settings.imageFloat)
				if model.settings.imageFloat {
					SizeField(title: "Images up to", width: $model.settings.imageFloatW, height: $model.settings.imageFloatH)
					Picker("Position", selection: $model.settings.imageFloatType) {
						Text("Top / left").tag(0)
						Text("Bottom / right").tag(1)
					}
				}
				SizeField(title: "Own page if at least", width: $model.settings.singlePageSizeW, height: $model.settings.singlePageSizeH)
				IntField(title: "…or wider than", value: $model.settings.singlePageWidth, suffix: "px")
				Picker("Full-page image size", selection: $model.settings.imageSizeType) {
					Text("Let the reader decide").tag(1)
					Text("Fit to screen shape").tag(3)
				}
				Toggle("Enlarge small full-page images", isOn: $model.settings.fitImage)
				Picker("Rotate wide images on tall screens", selection: $model.settings.rotateImage) {
					Text("Don't rotate").tag(0)
					Text("Rotate right").tag(1)
					Text("Rotate left").tag(2)
				}
				Toggle("Fixed-layout SVG pages (image-only books)", isOn: $model.settings.svgImage)
				Toggle("Float full-page images (Sony Reader)", isOn: $model.settings.imageFloatPage)
				Toggle("Float other images (Sony Reader)", isOn: $model.settings.imageFloatBlock)
			}
			Section("Processing") {
				IntField(title: "JPEG quality", value: $model.settings.jpegQuality, suffix: "(30–100)")
				Toggle("Shrink images wider than", isOn: $model.settings.resizeW)
				if model.settings.resizeW { IntField(title: "Max width", value: $model.settings.resizeNumW, suffix: "px") }
				Toggle("Shrink images taller than", isOn: $model.settings.resizeH)
				if model.settings.resizeH { IntField(title: "Max height", value: $model.settings.resizeNumH, suffix: "px") }
				Toggle("Adjust darkness (gamma)", isOn: $model.settings.gamma)
				if model.settings.gamma { FloatField(title: "Gamma (0.2 dark – 1.8 light)", value: $model.settings.gammaValue) }
			}
			Section("Trim scanned margins") {
				Toggle("Remove white margins", isOn: $model.settings.autoMargin)
				if model.settings.autoMargin {
					IntField(title: "Up to (left + right)", value: $model.settings.autoMarginLimitH, suffix: "%")
					IntField(title: "Up to (top + bottom)", value: $model.settings.autoMarginLimitV, suffix: "%")
					FloatField(title: "Then add back", value: $model.settings.autoMarginPadding, suffix: "%")
					IntField(title: "Count as white above", value: $model.settings.autoMarginWhiteLevel, suffix: "% brightness")
					Picker("Remove page numbers", selection: $model.settings.autoMarginNombre) {
						Text("No").tag(0)
						Text("At the top").tag(1)
						Text("At the bottom").tag(2)
						Text("Top and bottom").tag(3)
					}
					FloatField(title: "Page number height", value: $model.settings.autoMarginNombreSize, suffix: "%")
				}
			}
		}
	}
}

// MARK: - Style

struct StylePane: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		Pane {
			Section("Type") {
				Picker("Line height", selection: $model.settings.lineHeight) {
					ForEach([1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0] as [Float], id: \.self) { Text(String(format: "%.1f", $0)).tag($0) }
				}
				Picker("Font size", selection: $model.settings.fontSize) {
					ForEach(stride(from: 75, through: 125, by: 5).map { $0 }, id: \.self) { Text("\($0)%").tag($0) }
				}
				Toggle("Show bold (太字) as bold gothic", isOn: $model.settings.boldUseGothic)
				Toggle("Show gothic (ゴシック体) as bold gothic", isOn: $model.settings.gothicUseBold)
			}
			Section("Page margins (@page)") {
				MarginEditor(values: $model.settings.pageMargin, unit: $model.settings.pageMarginUnit)
			}
			Section("Text margins (html, for Sony Reader)") {
				MarginEditor(values: $model.settings.bodyMargin, unit: $model.settings.bodyMarginUnit)
			}
		}
	}
}

struct MarginEditor: View {
	@Binding var values: [String]
	@Binding var unit: Int

	var body: some View {
		HStack(spacing: 14) {
			ForEach(Array((["Top", "Right", "Bottom", "Left"] as [LocalizedStringKey]).enumerated()), id: \.offset) { i, label in
				VStack(spacing: 2) {
					TextField(label, text: Binding(get: { values.indices.contains(i) ? values[i] : "0" }, set: { if values.indices.contains(i) { values[i] = $0 } }))
						.multilineTextAlignment(.center)
						.frame(width: 54)
					Text(label).font(.caption2).foregroundStyle(.secondary)
				}
			}
			Picker("Unit", selection: $unit) {
				Text("em (字)").tag(0)
				Text("%").tag(1)
			}
			.labelsHidden()
			.fixedSize()
		}
	}
}

// MARK: - Web

struct WebPane: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		Pane {
			Section("Downloading") {
				FloatField(title: "Wait between pages", value: $model.settings.webInterval, suffix: "seconds")
				Text("Be kind to the sites: 0.5 seconds is the minimum.").font(.caption).foregroundStyle(.secondary)
				LabeledContent("Cache") {
					HStack {
						Text(model.settings.cachePath.isEmpty ? "~/Library/Caches/Aozora Ebooks" : (model.settings.cachePath as NSString).abbreviatingWithTildeInPath)
							.lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
						Button("Change…") {
							let panel = NSOpenPanel()
							panel.canChooseDirectories = true
							panel.canChooseFiles = false
							panel.canCreateDirectories = true
							if panel.runModal() == .OK, let url = panel.url { model.settings.cachePath = url.path }
						}
						Button("Reveal") {
							let url = model.settings.cachePath.isEmpty ? AozoraEpub.defaultWebCache : URL(fileURLWithPath: model.settings.cachePath)
							try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
							NSWorkspace.shared.open(url)
						}
					}
				}
				TextField("User agent (optional)", text: $model.settings.userAgent)
			}
			Section("Updates") {
				FloatField(title: "Count chapters fetched within", value: $model.settings.webModifiedExpire, suffix: "hours as new")
				Toggle("Only make a book when something changed", isOn: $model.settings.webConvertUpdated)
				Toggle("Only include new or changed chapters", isOn: $model.settings.webModifiedOnly)
				Toggle("…only the newest run of them", isOn: $model.settings.webModifiedTail).disabled(!model.settings.webModifiedOnly)
				Toggle("Only the latest chapters", isOn: $model.settings.webBeforeChapter)
				if model.settings.webBeforeChapter {
					IntField(title: "How many", value: $model.settings.webBeforeChapterCount, suffix: "chapters")
				}
			}
			Section("Supported sites") {
				Text(WebNovelDownloader.supportedHosts().joined(separator: " · "))
					.font(.callout)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
			}
		}
	}
}

// MARK: - Profiles

struct ProfilesPane: View {
	@Environment(AppModel.self) private var model
	@State private var newName = ""
	@State private var confirmReset = false

	var body: some View {
		Pane {
			Section("Saved settings") {
				if model.profiles.isEmpty {
					Text("Save the current settings to switch between setups, like one per reader.").foregroundStyle(.secondary)
				}
				ForEach(model.profiles) { profile in
					HStack {
						Text(profile.name)
						Spacer()
						Button("Use") { model.apply(profile) }
						Button(role: .destructive) { model.delete(profile) } label: { Image(systemName: "trash") }
							.buttonStyle(.borderless)
					}
				}
				HStack {
					TextField("Name", text: $newName)
					Button("Save Current Settings") {
						model.saveProfile(named: newName.isEmpty ? String(localized: "Profile \(model.profiles.count + 1)") : newName)
						newName = ""
					}
				}
			}
			Section("AozoraEpub3 compatibility") {
				Text("Profiles are saved as AozoraEpub3 .ini files, so they can move between the two apps.").font(.caption).foregroundStyle(.secondary)
				HStack {
					Button("Import .ini…") {
						let panel = NSOpenPanel()
						panel.allowedContentTypes = [UTType(filenameExtension: "ini") ?? .data]
						if panel.runModal() == .OK, let url = panel.url { model.importIni(url) }
					}
					Button("Export .ini…") {
						let panel = NSSavePanel()
						panel.nameFieldStringValue = "AozoraEpub3.ini"
						if panel.runModal() == .OK, let url = panel.url { model.exportIni(to: url) }
					}
					Button("Show Profiles Folder") { NSWorkspace.shared.open(AppPaths.profiles) }
				}
			}
			Section("Character substitutions") {
				Text("Put a replace.txt (tab-separated: character, replacement) in the app's support folder to swap characters during conversion.")
					.font(.caption).foregroundStyle(.secondary)
				Button("Show Support Folder") { NSWorkspace.shared.open(AppPaths.support) }
			}
			Section {
				Button("Reset All Settings…", role: .destructive) { confirmReset = true }
					.confirmationDialog("Reset every setting to the defaults?", isPresented: $confirmReset) {
						Button("Reset", role: .destructive) {
							var s = ConversionSettings()
							if let books = model.presets.first(where: { $0.file == "apple_books.ini" }) { s.apply(ini: books.ini) }
							model.settings = s
							model.presetName = "Apple Books (iPhone / iPad / Mac)"
						}
					}
			}
		}
	}
}
