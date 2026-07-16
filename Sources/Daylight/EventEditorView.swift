import SwiftUI

struct EventEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.daylightPalette) private var palette
    @State private var draft: EventDraft
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var attemptedSave = false

    init(model: AppModel, initialDraft: EventDraft) {
        self.model = model
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            Form {
                Section("Event") {
                    TextField("Title", text: $draft.title, prompt: Text("What’s happening?"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Event title")

                    Toggle("All-day event", isOn: $draft.isAllDay)

                    DatePicker(
                        "Starts",
                        selection: $draft.startDate,
                        displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Ends",
                        selection: $draft.endDate,
                        displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 88)
                        .accessibilityLabel("Event notes")
                }

                if attemptedSave, let message = draft.validationMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(message)")
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 520, height: 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(isSaving)
        .confirmationDialog(
            "Delete this event?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete Event", role: .destructive) {
                guard let eventID = draft.originalEventID else { return }
                isSaving = true
                Task {
                    _ = await model.delete(eventID: eventID)
                    isSaving = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the event from Apple Calendar on synced devices.")
        }
    }

    private var editorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.originalEventID == nil ? "New event" : "Edit event")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                Text("Changes sync through Apple Calendar")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if draft.originalEventID != nil {
                Button("Delete", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .disabled(isSaving)
            }
            Spacer()
            if isSaving {
                ProgressView().controlSize(.small)
            }
            Button {
                attemptedSave = true
                guard draft.validationMessage == nil else { return }
                isSaving = true
                Task {
                    _ = await model.save(draft)
                    isSaving = false
                }
            } label: {
                Text("Save")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.isLight ? Color.white : Color.black.opacity(0.84))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 36)
                    .background(palette.focus, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving)
        }
        .padding(20)
    }
}
