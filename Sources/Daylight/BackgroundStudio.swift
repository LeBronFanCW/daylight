import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImagePlayground
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

struct BackgroundReference: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let isImage: Bool
    let name: String
}

enum BackgroundCreationState: Equatable {
    case idle
    case understanding
    case generating
    case ready
    case failed(String)
}

@MainActor
final class BackgroundStudioModel: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var references: [BackgroundReference] = []
    @Published private(set) var state: BackgroundCreationState = .idle
    @Published private(set) var createdImageURL: URL?
    @Published var presentsImagePlayground = false
    @Published private(set) var refinedConcept = ""

    private let appModel: AppModel
    private let lockScreenManager: LockScreenWallpaperManager
    private let maximumReferences = 8

    init(appModel: AppModel, lockScreenManager: LockScreenWallpaperManager) {
        self.appModel = appModel
        self.lockScreenManager = lockScreenManager
    }

    var canCreate: Bool {
        (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !references.isEmpty)
            && state != .understanding
            && state != .generating
    }

    var sourceImageURL: URL? {
        references.first(where: \.isImage)?.url
    }

    var hasBaseImage: Bool { sourceImageURL != nil }

    func addReferences() {
        let panel = NSOpenPanel()
        panel.title = "Add inspiration"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf, .plainText, .rtf, .json]

        guard panel.runModal() == .OK else { return }
        do {
            for url in panel.urls.prefix(maximumReferences - references.count) {
                try importReference(url)
            }
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func remove(_ reference: BackgroundReference) {
        references.removeAll { $0.id == reference.id }
        try? FileManager.default.removeItem(at: reference.url)
    }

    func create() async {
        guard canCreate else { return }
        state = .understanding
        createdImageURL = nil

        do {
            let context = try textContext()
            refinedConcept = try await refineConcept(userPrompt: prompt, textContext: context)
            state = .generating
            try await generateBackground(concept: refinedConcept, instructions: prompt)
            state = .ready
        } catch {
            if error is CancellationError { return }
            state = .failed(error.localizedDescription)
        }
    }

    func generateWithImagePlayground() async {
        guard canCreate else { return }
        state = .understanding
        createdImageURL = nil
        do {
            let context = try textContext()
            refinedConcept = try await refineConcept(userPrompt: prompt, textContext: context)
            state = .idle
            presentsImagePlayground = true
        } catch {
            if error is CancellationError { return }
            state = .failed(error.localizedDescription)
        }
    }

    func receivePlaygroundImage(at temporaryURL: URL) {
        presentsImagePlayground = false
        do {
            try FileManager.default.createDirectory(at: creationsDirectory, withIntermediateDirectories: true)
            let destination = creationsDirectory.appendingPathComponent("daylight-\(UUID().uuidString).png")
            try Data(contentsOf: temporaryURL).write(to: destination, options: .atomic)
            createdImageURL = destination
            state = .ready
        } catch {
            state = .failed("Image Playground finished, but Daylight couldn’t save the image: \(error.localizedDescription)")
        }
    }

    func cancelImagePlayground() {
        presentsImagePlayground = false
        state = .idle
    }

    func applyBackground() {
        guard let createdImageURL else { return }
        appModel.setCustomBackground(createdImageURL)
        lockScreenManager.setEnabled(true)
        lockScreenManager.refreshNow()
        state = .ready
    }

    func useBaseImage() {
        guard let sourceImageURL else { return }
        state = .generating
        createdImageURL = nil
        do {
            try renderTransformedSource(at: sourceImageURL, instructions: "keep the original image unchanged")
            refinedConcept = "Original image, fitted to the Mac display without decorative overlays."
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func importReference(_ originalURL: URL) throws {
        guard references.count < maximumReferences else { throw StudioError.tooManyReferences }
        let values = try originalURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        guard let type = values.contentType,
              type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .json) else {
            throw StudioError.unsupportedFile
        }
        let size = values.fileSize ?? 0
        guard size <= 25_000_000 else { throw StudioError.fileTooLarge }

        try FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
        let ext = originalURL.pathExtension.isEmpty ? "data" : originalURL.pathExtension
        let destination = importsDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: originalURL, to: destination)
        references.append(BackgroundReference(
            id: UUID(),
            url: destination,
            isImage: type.conforms(to: .image),
            name: originalURL.lastPathComponent
        ))
    }

    private func textContext() throws -> String {
        var excerpts: [String] = []
        for reference in references where !reference.isImage {
            let ext = reference.url.pathExtension.lowercased()
            let text: String
            if ext == "pdf" {
                text = PDFDocument(url: reference.url)?.string ?? ""
            } else if ext == "rtf",
                      let attributed = try? NSAttributedString(url: reference.url, options: [:], documentAttributes: nil) {
                text = attributed.string
            } else {
                text = (try? String(contentsOf: reference.url, encoding: .utf8)) ?? ""
            }
            let trimmed = String(text.prefix(6_000)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { excerpts.append("\(reference.name):\n\(trimmed)") }
        }
        return excerpts.joined(separator: "\n\n")
    }

    private func refineConcept(userPrompt: String, textContext: String) async throws -> String {
        let request = """
        Create one concise, vivid Image Playground concept for a Mac wallpaper.
        Preserve the person's intent and reference material. Describe subject, composition, lighting,
        palette, atmosphere, and negative space. Avoid text, logos, UI, frames, and watermarks.
        Person's request: \(userPrompt.isEmpty ? "Use the attached references as the direction." : userPrompt)
        \(textContext.isEmpty ? "" : "File notes:\n\(textContext)")
        Return only the final visual concept in 90 words or fewer.
        """

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available else { return fallbackConcept(userPrompt, textContext) }
            let session = LanguageModelSession(model: model, instructions: "You are an expert wallpaper art director.")
            let response = try await session.respond(to: request)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        return fallbackConcept(userPrompt, textContext)
    }

    private func fallbackConcept(_ userPrompt: String, _ textContext: String) -> String {
        let base = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty { return base }
        if !textContext.isEmpty { return String(textContext.prefix(900)) }
        return "Create a spacious Mac wallpaper inspired by the supplied image, with balanced composition and room for desktop icons."
    }

    private func generateBackground(concept: String, instructions: String) async throws {
        if #available(macOS 27.0, *) {
            try renderPrivateBackground(concept: concept, instructions: instructions)
            return
        }

        guard #available(macOS 15.4, *) else { throw StudioError.imageGenerationUnavailable }

        let creator = try await ImageCreator()
        var concepts: [ImagePlaygroundConcept] = [.text(concept)]
        concepts.append(contentsOf: references.filter(\.isImage).compactMap { ImagePlaygroundConcept.image($0.url) })

        if #available(macOS 26.4, *) {
            var options = ImagePlaygroundOptions()
            options.personalization = .automatic
            for try await image in creator.images(for: concepts, style: .illustration, options: options, limit: 1) {
                try saveCreatedImage(image.cgImage)
                return
            }
        } else {
            for try await image in creator.images(for: concepts, style: .illustration, limit: 1) {
                try saveCreatedImage(image.cgImage)
                return
            }
        }

        throw StudioError.noImageCreated
    }

    private func renderPrivateBackground(concept: String, instructions: String) throws {
        if let sourceImageURL {
            try renderTransformedSource(at: sourceImageURL, instructions: instructions)
            return
        }

        let size = NSSize(width: 2880, height: 1800)
        let image = NSImage(size: size)
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        let bounds = NSRect(origin: .zero, size: size)
        let palette = wallpaperPalette(for: concept)

        NSGradient(colors: [palette[0], palette[1], palette[2]])?.draw(in: bounds, angle: -22)

        let seed = stableSeed(for: concept)
        for index in 0..<5 {
            let x = CGFloat((seed >> (index * 7)) & 0xFF) / 255
            let y = CGFloat((seed >> (index * 5 + 3)) & 0xFF) / 255
            let width = size.width * (0.38 + CGFloat(index % 3) * 0.11)
            let height = size.height * (0.42 + CGFloat((index + 1) % 3) * 0.12)
            let rect = NSRect(
                x: x * size.width - width * 0.45,
                y: y * size.height - height * 0.45,
                width: width,
                height: height
            )
            let color = palette[(index + 1) % palette.count]
            NSGradient(colors: [color.withAlphaComponent(0.48), color.withAlphaComponent(0)])?
                .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        }

        let shade = NSGradient(colors: [NSColor.clear, NSColor.black.withAlphaComponent(0.34)])
        shade?.draw(in: bounds, angle: -90)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw StudioError.imageEncodingFailed
        }
        try saveCreatedImageData(data)
    }

    private func renderTransformedSource(at url: URL, instructions: String) throws {
        guard var image = CIImage(contentsOf: url) else { throw StudioError.imageEncodingFailed }
        let target = CGRect(x: 0, y: 0, width: 2880, height: 1800)
        let lower = instructions.lowercased()
        let preserveOriginal = lower.isEmpty
            || lower.contains("unchanged")
            || lower.contains("as is")
            || lower.contains("use this image")
            || lower.contains("original")

        let scale = max(target.width / image.extent.width, target.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translatedX = target.midX - image.extent.midX
        let translatedY = target.midY - image.extent.midY
        image = image.transformed(by: CGAffineTransform(translationX: translatedX, y: translatedY))

        if !preserveOriginal {
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.brightness = lower.contains("bright") || lower.contains("sunlit") ? 0.10
                : (lower.contains("dark") || lower.contains("moody") || lower.contains("night") ? -0.16 : 0)
            controls.contrast = lower.contains("high contrast") || lower.contains("dramatic") ? 1.18
                : (lower.contains("soft contrast") || lower.contains("low contrast") ? 0.88 : 1)
            controls.saturation = lower.contains("black and white") || lower.contains("monochrome") ? 0
                : (lower.contains("vivid") || lower.contains("colorful") ? 1.28
                    : (lower.contains("muted") || lower.contains("desaturated") ? 0.72 : 1))
            image = controls.outputImage ?? image

            if lower.contains("warm") || lower.contains("golden") || lower.contains("sepia") {
                let sepia = CIFilter.sepiaTone()
                sepia.inputImage = image
                sepia.intensity = lower.contains("sepia") ? 0.72 : 0.22
                image = sepia.outputImage ?? image
            }

            if lower.contains("blur") || lower.contains("dreamy") || lower.contains("soft focus") {
                let blur = CIFilter.gaussianBlur()
                blur.inputImage = image.clampedToExtent()
                blur.radius = lower.contains("slight") ? 4 : 12
                image = (blur.outputImage ?? image).cropped(to: target)
            }
        }

        image = image.cropped(to: target)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(image, from: target) else {
            throw StudioError.imageEncodingFailed
        }
        try saveCreatedImage(cgImage)
    }

    private func wallpaperPalette(for concept: String) -> [NSColor] {
        let words = concept.lowercased()
        if words.contains("desert") || words.contains("peach") || words.contains("sunset") {
            return [NSColor(hex: 0x171B38), NSColor(hex: 0xEF8B72), NSColor(hex: 0xF5C69B), NSColor(hex: 0x65538E)]
        }
        if words.contains("forest") || words.contains("green") || words.contains("botanical") {
            return [NSColor(hex: 0x071F1B), NSColor(hex: 0x1E6655), NSColor(hex: 0x9CCB8B), NSColor(hex: 0xD8B56A)]
        }
        if words.contains("ocean") || words.contains("blue") || words.contains("water") {
            return [NSColor(hex: 0x071B36), NSColor(hex: 0x176B87), NSColor(hex: 0x6CC5D3), NSColor(hex: 0x8D7FDB)]
        }
        if words.contains("dark") || words.contains("night") || words.contains("space") {
            return [NSColor(hex: 0x080A18), NSColor(hex: 0x26234F), NSColor(hex: 0x784C9E), NSColor(hex: 0xDA7C8C)]
        }
        return [NSColor(hex: 0x18243A), NSColor(hex: 0x4F6E86), NSColor(hex: 0xD38A68), NSColor(hex: 0xE8C79A)]
    }

    private func stableSeed(for text: String) -> UInt64 {
        text.utf8.reduce(1_469_598_103_934_665_603) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private func saveCreatedImage(_ image: CGImage) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw StudioError.imageEncodingFailed
        }
        try saveCreatedImageData(data)
    }

    private func saveCreatedImageData(_ data: Data) throws {
        try FileManager.default.createDirectory(at: creationsDirectory, withIntermediateDirectories: true)
        let destination = creationsDirectory.appendingPathComponent("daylight-\(UUID().uuidString).png")
        try data.write(to: destination, options: .atomic)
        createdImageURL = destination
    }

    private var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Daylight", isDirectory: true)
    }

    private var importsDirectory: URL { supportDirectory.appendingPathComponent("Imports", isDirectory: true) }
    private var creationsDirectory: URL { supportDirectory.appendingPathComponent("Creations", isDirectory: true) }
}

private enum StudioError: LocalizedError {
    case tooManyReferences, unsupportedFile, fileTooLarge
    case imageGenerationUnavailable, noImageCreated, imageEncodingFailed
    var errorDescription: String? {
        switch self {
        case .tooManyReferences: "Add up to eight references at a time."
        case .unsupportedFile: "Use images, PDFs, text, RTF, or JSON files."
        case .fileTooLarge: "Each reference must be smaller than 25 MB."
        case .imageGenerationUnavailable: "Background generation requires Apple Intelligence and Image Playground."
        case .noImageCreated: "Image Playground finished without creating an image. Try a different description."
        case .imageEncodingFailed: "Daylight couldn’t save the generated image."
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

@MainActor
final class BackgroundStudioWindowController: NSObject, NSWindowDelegate {
    private let studioModel: BackgroundStudioModel
    private var window: NSWindow?

    init(appModel: AppModel, lockScreenManager: LockScreenWallpaperManager) {
        studioModel = BackgroundStudioModel(appModel: appModel, lockScreenManager: lockScreenManager)
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Create Background"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 780, height: 580)
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: BackgroundStudioView(model: studioModel))
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct BackgroundStudioView: View {
    @ObservedObject var model: BackgroundStudioModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var supportsImagePlayground: Bool {
        if #available(macOS 15.1, *) {
            return ImagePlaygroundViewController.isAvailable
        }
        return false
    }

    var body: some View {
        playgroundPresenter(content)
    }

    private var content: some View {
        VStack(spacing: 0) {
            studioHeader

            Divider()

            HSplitView {
                editor
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 430)
                preview
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.orange)
    }

    private var studioHeader: some View {
        VStack(spacing: 7) {
            Text("Create any background")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Describe what you want, add optional inspiration, then approve the finished image.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.hasBaseImage ? "WHAT SHOULD CHANGE?" : "YOUR IDEA")
                        .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        if model.prompt.isEmpty {
                            Text(model.hasBaseImage
                                 ? "Example: make it warmer, darker, monochrome, vivid, or softly blurred."
                                 : "Example: a photorealistic alpine lake at sunrise with open space for desktop icons.")
                                .font(.body).foregroundStyle(.tertiary)
                                .padding(.horizontal, 15).padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $model.prompt)
                            .font(.body)
                            .frame(minHeight: 132)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel(model.hasBaseImage ? "Describe changes to the base image" : "Describe your background")
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.55)) }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                    Text("BASE IMAGE & REFERENCES").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.references.count)/8").font(.caption).foregroundStyle(.tertiary)
                    }
                    if model.references.isEmpty {
                        Button(action: model.addReferences) {
                            Label("Choose a base image or add files", systemImage: "photo.badge.plus")
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        ForEach(model.references) { reference in
                            HStack(spacing: 10) {
                                if reference.isImage, let image = NSImage(contentsOf: reference.url) {
                                    Image(nsImage: image)
                                        .resizable().scaledToFill()
                                        .frame(width: 54, height: 38)
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                } else {
                                    Image(systemName: "doc.text")
                                        .frame(width: 28, height: 28)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reference.name).lineLimit(1)
                                    Text(reference.url == model.sourceImageURL ? "BASE IMAGE" : "REFERENCE")
                                        .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove", systemImage: "xmark") { model.remove(reference) }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                            }
                        }
                        Button("Add more", systemImage: "plus", action: model.addReferences)
                            .disabled(model.references.count >= 8)
                    }
                }

                if case let .failed(message) = model.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await model.generateWithImagePlayground() }
                } label: {
                    HStack {
                        if model.state == .understanding {
                            ProgressView().controlSize(.small)
                        }
                        Label(playgroundButtonTitle, systemImage: "apple.intelligence")
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canCreate || !supportsImagePlayground)

                if model.hasBaseImage {
                    Button {
                        Task { await model.create() }
                    } label: {
                        Label("Quick Private Edit", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!model.canCreate)

                    Button("Use Image as Background", systemImage: "display", action: model.useBaseImage)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(model.state == .understanding || model.state == .generating)
                } else {
                    Button {
                        Task { await model.create() }
                    } label: {
                        Label("Create Abstract Privately", systemImage: "circle.hexagongrid")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!model.canCreate)
                }

                Label(generationDisclosure, systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)

                if !supportsImagePlayground {
                    Label("Image Playground is unavailable. Check Apple Intelligence and image generation in System Settings.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(28)
        }
    }

    private var preview: some View {
        ZStack {
            Color.black.opacity(0.94)
            if let url = model.createdImageURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill().clipped()
                    .transition(.opacity)
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Ready for your Mac", systemImage: "checkmark.circle.fill")
                        Button("Apply Background", systemImage: "display") { model.applyBackground() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(18)
                    .background(.regularMaterial)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 54, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Your background will appear here")
                        .font(.title3.weight(.medium)).foregroundStyle(.white)
                    Text("Daylight quietly turns your direction into a wallpaper and shows the finished result here.")
                        .font(.callout).foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                }
                .padding(30)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.createdImageURL)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.createdImageURL == nil ? "Background preview, empty" : "Created background preview")
    }

    private var playgroundButtonTitle: String {
        switch model.state {
        case .understanding: "Understanding your idea…"
        default: model.hasBaseImage ? "Reimagine in Image Playground" : "Generate with Image Playground"
        }
    }

    private var generationDisclosure: String {
        if #available(macOS 27.0, *) {
            return "macOS 27 requires Apple’s secure Image Playground sheet for full generation. Apple manages privacy, styles, availability, and usage limits."
        }
        return "Image Playground uses Apple Intelligence and returns only the image you approve to Daylight."
    }

    @ViewBuilder
    private func playgroundPresenter<Content: View>(_ content: Content) -> some View {
        if #available(macOS 15.1, *) {
            if let sourceURL = model.sourceImageURL {
                content.imagePlaygroundSheet(
                    isPresented: $model.presentsImagePlayground,
                    concept: model.refinedConcept,
                    sourceImageURL: sourceURL,
                    onCompletion: model.receivePlaygroundImage,
                    onCancellation: model.cancelImagePlayground
                )
            } else {
                content.imagePlaygroundSheet(
                    isPresented: $model.presentsImagePlayground,
                    concept: model.refinedConcept,
                    sourceImage: nil,
                    onCompletion: model.receivePlaygroundImage,
                    onCancellation: model.cancelImagePlayground
                )
            }
        } else {
            content
        }
    }
}
