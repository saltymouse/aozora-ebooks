import Foundation
import AozoraKit

// Command-line converter. Options follow the Java AozoraEpub3 CLI.

let usage = """
usage: aozora [options] input_files (txt, txtz, zip, cbz, rar, or a web novel URL)
  -i, --ini FILE     load settings from an AozoraEpub3 .ini / profile / preset
  -d, --dst DIR      output directory (default: next to the input)
  -enc ENC           input encoding: MS932 (default) or UTF-8
  -ext EXT           output extension: .epub (default), .kepub.epub, .fxl.kepub.epub, .mobi, .mobi+.epub
  -t N               title layout 0-5 (0: title→author, 1: author→title, 2: title→author w/ subtitle,
                     3: title only, 4: title+author only, 5: none)
  -tf                take title/author from the file name
  -c COVER           cover: 0 = first illustration, 1 = image with the same name, or a file/URL
  -of                name the output after the input file (not the title)
  -hor               horizontal text (default vertical)
  -q                 quiet: only warnings and errors
  --dump-ini         print the effective settings as an .ini and exit
  -h, --help         show this help
"""

func run() -> Int32 {
	var settings = ConversionSettings()
	settings.confirm = false
	var files: [String] = []
	var dst: URL?
	var quiet = false
	var dumpIni = false
	var args = CommandLine.arguments.dropFirst().makeIterator()

	func value(_ flag: String) -> String {
		guard let v = args.next() else { FileHandle.standardError.write(Data("\(flag) needs a value\n".utf8)); exit(2) }
		return v
	}

	var overrides: [(inout ConversionSettings) -> Void] = []
	while let a = args.next() {
		switch a {
		case "-h", "--help": print(usage); exit(0)
		case "-i", "--ini":
			let path = value(a)
			guard let data = FileManager.default.contents(atPath: path) else { FileHandle.standardError.write(Data("-i : ini file not exist. \(path)\n".utf8)); exit(1) }
			settings.apply(ini: JavaProperties.parse(data))
			settings.confirm = false
		case "-d", "--dst":
			let path = value(a)
			var isDir: ObjCBool = false
			guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { FileHandle.standardError.write(Data("-d : dst path not exist. \(path)\n".utf8)); exit(1) }
			dst = URL(fileURLWithPath: path)
		case "-enc": let v = value(a); overrides.append { $0.encoding = v.uppercased() == "UTF-8" ? .utf8 : .shiftJIS }
		case "-ext": let v = value(a); overrides.append { $0.ext = v }
		case "-t": let v = Int(value(a)) ?? 0; overrides.append { $0.titleType = TitleType(rawValue: v) ?? .titleAuthor }
		case "-tf": overrides.append { $0.useFileName = true }
		case "-c":
			let v = value(a)
			overrides.append {
				switch v {
				case "0": $0.cover = .firstIllustration
				case "1": $0.cover = .sameNameImage
				default: $0.cover = .file(v)
				}
			}
		case "-of": overrides.append { $0.autoFileName = false }
		case "-hor": overrides.append { $0.vertical = false }
		case "-q": quiet = true
		case "--dump-ini": dumpIni = true
		default:
			if a.hasPrefix("-") { FileHandle.standardError.write(Data("unknown option \(a)\n\(usage)\n".utf8)); exit(2) }
			files.append(a)
		}
	}
	for o in overrides { o(&settings) }
	if dumpIni {
		print(JavaProperties.serialize(settings.ini), terminator: "")
		return 0
	}
	if files.isEmpty { print(usage); exit(2) }

	let quietOutput = quiet
	let log = Log { entry in
		if quietOutput && (entry.level == .info || entry.level == .plain) { return }
		print(entry.text)
	}
	let engine = AozoraEpub(settings: settings, log: log)
	let webEngine = AozoraEpub(settings: AozoraEpub.webSettings(settings), log: log)
	var failed = false
	for path in files {
		log.println("--------")
		do {
			if path.hasPrefix("http://") || path.hasPrefix("https://") {
				let cache = settings.cachePath.isEmpty ? AozoraEpub.defaultWebCache : URL(fileURLWithPath: settings.cachePath)
				let downloads = dst ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
				let fixed = settings
				guard let local = try runBlocking({ try await AozoraEpub.fetch(path, settings: fixed, cacheDirectory: cache, downloadDirectory: downloads, log: log) }) else {
					failed = true
					continue
				}
				let e = local.pathExtension == "txt" ? webEngine : engine
				for book in try e.prepare(local) { try e.convert(book, dstDirectory: downloads) }
			} else {
				for book in try engine.prepare(URL(fileURLWithPath: path)) {
					try engine.convert(book, dstDirectory: dst)
				}
			}
		} catch {
			log.println("エラーが発生しました : \(error.localizedDescription)")
			failed = true
		}
	}
	return failed ? 1 : 0
}

/// Runs async work from the synchronous CLI.
func runBlocking<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
	nonisolated(unsafe) var result: Result<T, Error>!
	let sem = DispatchSemaphore(value: 0)
	Task.detached {
		do { result = .success(try await body()) } catch { result = .failure(error) }
		sem.signal()
	}
	sem.wait()
	return try result.get()
}

exit(run())
