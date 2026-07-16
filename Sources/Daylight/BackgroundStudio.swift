import AppKit
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

    var name: String { url.lastPathComponent }
}

enum BackgroundCreationState: Equatable {
    case idle
    case understanding
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
    }

    var sourceImageURL: URL? {
        references.first(where: \.isImage)?.url
    }

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
            state = .idle
            presentsImagePlayground = true
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func receiveCreatedImage(at temporaryURL: URL) {
        do {
            try FileManager.default.createDirectory(at: creationsDirectory, withIntermediateDirectories: true)
            let destination = creationsDirectory.appendingPathComponent("daylight-\(UUID().uuidString).png")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: temporaryURL, to: destination)
            createdImageURL = destination
            state = .ready
        } catch {
            state = .failed("The image was created, but Daylight couldn’t save it: \(error.localizedDescription)")
        }
    }

    func applyBackground() {
        guard let createdImageURL else { return }
        appModel.setCustomBackground(createdImageURL)
        lockScreenManager.setEnabled(true)
        lockScreenManager.refreshNow()
        state = .ready
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
        references.append(BackgroundReference(id: UUID(), url: destination, isImage: type.conforms(to: .image)))
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

    private var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Daylight", isDirectory: true)
    }

    private var importsDirectory: URL { supportDirectory.appendingPathComponent("Imports", isDirectory: true) }
    private var creationsDirectory: URL { supportDirectory.appendingPathComponent("Creations", isDirectory: true) }
}

private enum StudioError: LocalizedError {
    case tooManyReferences, unsupportedFile, fileTooLarge
    var errorDescription: String? {
        switch self {
        case .tooManyReferences: "Add up to eight references at a time."
        case .unsupportedFile: "Use images, PDFs, text, RTF, or JSON files."
        case .fileTooLarge: "Each reference must be smaller than 25 MB."
        }
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
        HSplitView {
            editor
                .frame(minWidth: 330, idealWidth: 370, maxWidth: 430)
            preview
                .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.orange)
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create a background")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Describe the feeling. Add files for context or an image for Image Playground to transform.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR IDEA").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                    TextEditor(text: $model.prompt)
                        .font(.body)
                        .frame(minHeight: 132)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.55)) }
                        .accessibilityLabel("Describe your background")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("INSPIRATION").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.references.count)/8").font(.caption).foregroundStyle(.tertiary)
                    }
                    if model.references.isEmpty {
                        Button(action: model.addReferences) {
                            Label("Add images or files", systemImage: "paperclip")
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        ForEach(model.references) { reference in
                            HStack(spacing: 10) {
                                Image(systemName: reference.isImage ? "photo" : "doc.text")
                                    .frame(width: 28, height: 28)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                                Text(reference.name).lineLimit(1)
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
                    Task { await model.create() }
                } label: {
                    HStack {
                        if model.state == .understanding { ProgressView().controlSize(.small) }
                        Label(model.state == .understanding ? "Understanding your idea…" : "Create with Apple Intelligence", systemImage: "sparkles")
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canCreate || !supportsImagePlayground)

                if !supportsImagePlayground {
                    Text("Image Playground is unavailable. Turn on Apple Intelligence and image generation in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Foundation Models refines your direction. Image Playground uses Apple’s private system service.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
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
                    Text("Daylight uses Foundation Models to shape your direction, then opens Image Playground to create the final image.")
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

    @ViewBuilder
    private func playgroundPresenter<Content: View>(_ content: Content) -> some View {
        if #available(macOS 15.1, *) {
            if let sourceURL = model.sourceImageURL {
                content.imagePlaygroundSheet(
                    isPresented: $model.presentsImagePlayground,
                    concept: model.refinedConcept,
                    sourceImageURL: sourceURL,
                    onCompletion: model.receiveCreatedImage,
                    onCancellation: {}
                )
            } else {
                content.imagePlaygroundSheet(
                    isPresented: $model.presentsImagePlayground,
                    concept: model.refinedConcept,
                    sourceImage: nil,
                    onCompletion: model.receiveCreatedImage,
                    onCancellation: {}
                )
            }
        } else {
            content
        }
    }
}
