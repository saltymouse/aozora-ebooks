import Foundation

/// Writer for image-only archives (comics, scanned books): one image per page
/// (port of `Epub3ImageWriter`).
final class EpubImageWriter: EpubWriter {
	override var templateFiles: [String] {
		let css = Self.opsPath + Self.cssPath
		if params.isKindle { return ["META-INF/container.xml", css + "kindle_image.css"] }
		if params.isSvgImage { return ["META-INF/container.xml", css + "svg_image.css"] }
		if bookInfo?.vertical == true { return ["META-INF/container.xml", css + "vertical_image.css"] }
		return ["META-INF/container.xml", css + "horizontal_image.css"]
	}

	override func writeSections(_ converter: AozoraConverter, _ lines: [String]?, _ srcFile: URL, _ srcExt: String) throws {
		var fileNames: [String?] = []
		var pageNum = 0
		for srcFilePath in imageInfoReader.imageFileNames {
			if canceled { return }
			pageNum += 1
			fileNames.append(getImageFilePath(srcFilePath.jtrim(), pageNum))
		}

		var archivePathLength = 0
		if let entry = bookInfo.textEntryName { archivePathLength = entry.indexOf("/") + 1 }
		try ArchiveReader(url: srcFile).forEach { entry, read in
			guard !entry.isDirectory else { return true }
			try writeArchiveImage(entry.name.jsub(archivePathLength), read())
			return !canceled
		}
		if canceled { return }

		let imageTag = converter.getChukiValue("画像")?[0] ?? "%s"
		let imageEnd = converter.getChukiValue("画像終わり")?[0] ?? ""
		for (n, srcFilePath) in imageInfoReader.imageFileNames.enumerated() {
			if canceled { return }
			if let fileName = fileNames[n] {
				if params.isSvgImage {
					try printSvgImageSection(srcFilePath)
				} else {
					startImageSection(srcFilePath)
					write(javaFormat(imageTag, fileName))
					write(imageEnd)
					try endSection()
				}
			}
			addProgress(1)
		}
	}

	private func startImageSection(_ srcImageFilePath: String) {
		sectionIndex += 1
		let sectionId = Self.format4(sectionIndex)
		let sectionInfo = SectionInfo(sectionId)
		sectionInfo.imagePage = true
		if let info = imageInfoReader.imageInfo(srcImageFilePath) {
			let d = Double(params.dispW) / Double(params.dispH)
			let hw = Double(info.height) / Double(info.width)
			if Double(info.width) / Double(info.height) >= d {
				if params.rotateAngle != 0 && params.dispW < params.dispH && hw < d {
					info.rotateAngle = params.rotateAngle
					if params.imageSizeType != SectionInfo.imageSizeTypeAuto { sectionInfo.imageFitH = true }
				} else {
					if params.imageSizeType == SectionInfo.imageSizeTypeHeight { sectionInfo.imageHeight = hw * d }
					else if params.imageSizeType == SectionInfo.imageSizeTypeAspect { sectionInfo.imageFitW = true }
				}
			} else {
				if params.rotateAngle != 0 && params.dispW > params.dispH && hw > d {
					info.rotateAngle = params.rotateAngle
					if params.imageSizeType == SectionInfo.imageSizeTypeHeight { sectionInfo.imageHeight = hw * d }
					else if params.imageSizeType == SectionInfo.imageSizeTypeAspect { sectionInfo.imageFitW = true }
				} else if params.imageSizeType != SectionInfo.imageSizeTypeAuto {
					sectionInfo.imageFitH = true
				}
			}
		}
		sectionInfos.append(sectionInfo)
		if sectionIndex == 1 || sectionIndex % 5 == 0 { addChapter(nil, String(sectionIndex), 0) }
		beginSection(sectionId, sectionInfo, template: Self.opsPath + Self.xhtmlPath + "xhtml_header.vm")
	}

	private func printSvgImageSection(_ srcImageFilePath: String) throws {
		sectionIndex += 1
		let sectionId = Self.format4(sectionIndex)
		let sectionInfo = SectionInfo(sectionId)
		sectionInfo.imagePage = true
		sectionInfos.append(sectionInfo)
		if sectionIndex == 1 || sectionIndex % 5 == 0 { addChapter(nil, String(sectionIndex), 0) }
		velocityContext.put("imageInfo", imageInfoReader.imageInfo(srcImageFilePath))
		beginSection(sectionId, sectionInfo, template: Self.opsPath + Self.xhtmlPath + "svg_image.vm")
		// the SVG template is a complete page: no footer
		try finishSectionWithoutFooter()
	}

	/// Image-only books number images by page and take every format the archive provides.
	override func getImageFilePath(_ srcImageFileName: String, _ lineNum: Int) -> String? {
		var isCover = false
		imageIndex += 1
		let ext = (srcImageFileName as NSString).pathExtension.lowercased()
		let imageId = Self.format4(imageIndex)
		let imageFileName = Self.imagesPath + imageId + "." + ext
		guard let info = imageInfoReader.imageInfo(srcImageFileName) else { return nil }
		info.id = imageId
		info.outFileName = imageId + "." + ext
		if !info.ext.matches("^(png|jpeg|gif|jpg)$") {
			log.error(lineNum, "画像フォーマットエラー", srcImageFileName)
			return nil
		}
		if imageIndex - 1 == bookInfo.coverImageIndex {
			info.isCover = true
			isCover = true
		}
		imageInfos.append(info)
		if bookInfo.insertCoverPage && isCover { return nil }
		return "../" + imageFileName
	}
}
