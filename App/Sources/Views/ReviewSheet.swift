import SwiftUI
import AozoraKit
import UniformTypeIdentifiers

/// Check and adjust a book before it's bound: title, furigana, cover and contents.
struct ReviewSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	let job: BookJob

	@State private var title = ""
	@State private var titleAs = ""
	@State private var creator = ""
	@State private var creatorAs = ""
	@State private var publisher = ""
	@State private var titleType: TitleType = .titleAuthor
	@State private var pubFirst = false
	@State private var toc: [TocRow] = []
	@State private var cover = CoverState()
	@State private var output = ""
	@State private var showTitleAlert = false

	var body: some View {
		VStack(spacing: 0) {
			HStack(alignment: .top, spacing: 24) {
				CoverEditor(job: job, state: $cover, title: title, author: creator)
					.frame(width: 300)
				VStack(alignment: .leading, spacing: 16) {
					metadata
					if !(job.book?.isImageOnly ?? true) {
						TocEditor(rows: $toc)
					} else {
						ContentUnavailableView("Picture book", systemImage: "photo.on.rectangle", description: Text("Pages follow the image order in the archive."))
					}
				}
			}
			.padding(24)
			Divider()
			footer
				.padding(.horizontal, 24)
				.padding(.vertical, 14)
		}
		.frame(minWidth: 880, idealWidth: 960, minHeight: 640, idealHeight: 700)
		.background(PaperBackground())
		.onAppear(perform: load)
		.alert("A book needs a title", isPresented: $showTitleAlert) {
			Button("OK") {}
		}
		.interactiveDismissDisabled()
	}

	private var metadata: some View {
		Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
			GridRow {
				Text("Title").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
				TextField("Title", text: $title).font(.system(.title3, design: .serif)).frame(maxWidth: .infinity)
				TextField("Reading (ふりがな)", text: $titleAs).frame(width: 170)
			}
			GridRow {
				Text("Author").foregroundStyle(.secondary)
				TextField("Author", text: $creator).frame(maxWidth: .infinity)
				TextField("Reading (ふりがな)", text: $creatorAs).frame(width: 170)
			}
			GridRow {
				Text("Publisher").foregroundStyle(.secondary)
				TextField("Optional", text: $publisher).gridCellColumns(2)
			}
			if !(job.book?.isImageOnly ?? true) {
				GridRow {
					Text("Read from").foregroundStyle(.secondary)
					HStack {
						Picker("Title lines", selection: $titleType) {
							ForEach(TitleType.allCases, id: \.self) { t in Text(t.displayName).tag(t) }
						}
						.labelsHidden()
						.fixedSize()
						Button("Re-read") { reread() }
							.fixedSize()
							.help("Read the title and author again from the top of the text")
						Spacer()
						Button("Use File Name") { fromFileName() }
							.fixedSize()
							.help("Use “[Author] Title” from the file name")
					}
					.gridCellColumns(2)
				}
				GridRow {
					Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
					Toggle("The first line is the publisher", isOn: $pubFirst)
						.gridCellColumns(2)
				}
			}
			GridRow {
				Text("Saves as").foregroundStyle(.secondary)
				Text(output)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
					.gridCellColumns(2)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var footer: some View {
		@Bindable var model = model
		return HStack {
			Toggle("Review every book", isOn: $model.settings.confirm)
				.help("Turn off to convert straight away next time")
			Spacer()
			Button("Stop All", role: .cancel) {
				model.finishReview(.cancelAll)
				dismiss()
			}
			Button("Skip") {
				commit()
				model.finishReview(.skip)
				dismiss()
			}
			Button("Bind Book") {
				guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { showTitleAlert = true; return }
				commit()
				model.finishReview(.convert)
				dismiss()
			}
			.keyboardShortcut(.defaultAction)
			.buttonStyle(.borderedProminent)
			.tint(Washi.vermilion)
		}
		.controlSize(.large)
	}

	private func load() {
		guard let book = job.book else { return }
		title = book.title
		titleAs = book.titleAs ?? ""
		creator = book.creator
		creatorAs = book.creatorAs ?? ""
		publisher = book.publisher ?? ""
		titleType = model.settings.titleType
		pubFirst = model.settings.pubFirst
		toc = book.tocEntries.map { TocRow(lineNum: $0.lineNum, kind: $0.typeId, pageBreak: $0.pageBreakChapter, name: $0.chapterName ?? "", selected: true) }
		cover = CoverState(book: book, image: job.cover)
		Task { output = (await model.plannedOutput(for: job))?.lastPathComponent ?? "" }
	}

	private func reread() {
		guard let book = job.book else { return }
		book.reloadTitle(titleType, pubFirst: pubFirst)
		title = book.title
		creator = book.creator
		publisher = book.publisher ?? ""
	}

	private func fromFileName() {
		guard let book = job.book else { return }
		let t = BookInfo.fileTitleCreator(book.srcFile.lastPathComponent)
		title = t.title ?? ""
		creator = t.creator ?? ""
	}

	private func commit() {
		guard let book = job.book else { return }
		book.title = title.trimmingCharacters(in: .whitespaces)
		book.creator = creator.trimmingCharacters(in: .whitespaces)
		book.titleAs = titleAs.trimmingCharacters(in: .whitespaces)
		book.creatorAs = creatorAs.trimmingCharacters(in: .whitespaces)
		book.publisher = publisher.trimmingCharacters(in: .whitespaces)
		if book.creator.isEmpty { book.bookInfo.creatorLine = -1 }
		book.applyToc(toc.map { ($0.lineNum, $0.selected, $0.name) })
		let choice = cover.resolve(coverW: model.settings.coverW, coverH: model.settings.coverH, keepOriginal: model.settings.replaceCover, title: title, author: creator)
		book.setCover(choice)
		model.chosenCover[ObjectIdentifier(book)] = choice
		job.title = book.title
		job.author = book.creator
		job.cover = book.coverPreview()
	}
}

extension TitleType {
	var displayName: String {
		switch self {
		case .titleAuthor: return String(localized: "Title, then author")
		case .authorTitle: return String(localized: "Author, then title")
		case .subtitleAuthor: return String(localized: "Title, subtitle, author")
		case .titleOnly: return String(localized: "Title only (1 line)")
		case .titleAuthorOnly: return String(localized: "Title and author only (2 lines)")
		case .none: return String(localized: "No title lines")
		}
	}
}

// MARK: - Table of contents

struct TocRow: Identifiable, Hashable {
	var id: Int { lineNum }
	let lineNum: Int
	let kind: String
	let pageBreak: Bool
	var name: String
	var selected: Bool
}

/// The TOC candidates with checkboxes and editable names.
struct TocEditor: View {
	@Binding var rows: [TocRow]

	private static let kinds: [(String, String)] = [
		("改", String(localized: "After page breaks")), ("見", String(localized: "見出し headings")), ("大", "大見出し"), ("中", "中見出し"), ("小", "小見出し"),
		("章", String(localized: "Chapter names (第〜章, 序, プロローグ…)")), ("数", String(localized: "Numbered lines")),
		("他", String(localized: "Your pattern")), ("題", String(localized: "Title")),
	]

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Table of Contents").font(.headline)
				Text("\(rows.filter(\.selected).count) of \(rows.count)").foregroundStyle(.secondary)
				Spacer()
				ForEach(Self.kinds.filter { k in rows.contains { kindOf($0) == k.0 } }, id: \.0) { kind in
					let all = rows.filter { kindOf($0) == kind.0 }.allSatisfy(\.selected)
					Button(kind.0) {
						for i in rows.indices where kindOf(rows[i]) == kind.0 { rows[i].selected = !all }
					}
					.buttonStyle(.bordered)
					.tint(all ? Washi.vermilion : nil)
					.help("Toggle all: \(kind.1)")
				}
				Button("All") {
					let allOn = rows.allSatisfy(\.selected)
					for i in rows.indices { rows[i].selected = !allOn }
				}
				.buttonStyle(.bordered)
			}
			Table($rows) {
				TableColumn("") { $row in
					Toggle("", isOn: $row.selected).labelsHidden()
				}
				.width(22)
				TableColumn("Kind") { $row in
					Text(kindOf(row))
						.font(.caption.bold())
						.padding(.horizontal, 5)
						.padding(.vertical, 1)
						.background(Capsule().fill(Washi.indigo.opacity(0.12)))
				}
				.width(40)
				TableColumn("Line") { $row in
					Text("\(row.lineNum + 1)").monospacedDigit().foregroundStyle(.secondary)
				}
				.width(48)
				TableColumn("Heading") { $row in
					TextField("", text: $row.name)
						.textFieldStyle(.plain)
						.opacity(row.selected ? 1 : 0.45)
				}
			}
			.tableStyle(.bordered(alternatesRowBackgrounds: true))
		}
	}

	private func kindOf(_ row: TocRow) -> String {
		row.kind.isEmpty ? (row.pageBreak ? "改" : "") : row.kind
	}
}
