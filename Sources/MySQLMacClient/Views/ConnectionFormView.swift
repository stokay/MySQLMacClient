import SwiftUI

struct ConnectionFormView: View {
    @ObservedObject var connectionStore: ConnectionStore
    @ObservedObject var appState: AppState
    @StateObject private var viewModel: ConnectionFormViewModel
    @State private var connectionPendingDeletion: ConnectionProfile?

    init(connectionStore: ConnectionStore, appState: AppState) {
        self.connectionStore = connectionStore
        self.appState = appState
        _viewModel = StateObject(wrappedValue: ConnectionFormViewModel(connectionStore: connectionStore))
    }

    var body: some View {
        HSplitView {
            savedConnectionsList
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            form
                .frame(minWidth: 380, maxWidth: .infinity)
        }
        .frame(minWidth: 640, minHeight: 480)
        .overlay(alignment: .topTrailing) {
            AppearancePickerView()
                .padding(12)
        }
    }

    private var savedConnectionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Kayıtlı Bağlantılar")
                .font(.headline)
                .padding(12)

            if connectionStore.connections.isEmpty {
                Text("Henüz kayıtlı bağlantı yok.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.horizontal, 12)
                Spacer()
            } else {
                List(connectionStore.connections) { profile in
                    savedConnectionRow(profile)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .confirmationDialog(
            "'\(connectionPendingDeletion?.name ?? "")' bağlantısı silinsin mi?",
            isPresented: Binding(
                get: { connectionPendingDeletion != nil },
                set: { if !$0 { connectionPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let profile = connectionPendingDeletion {
                    viewModel.delete(profile)
                }
                connectionPendingDeletion = nil
            }
            Button("İptal", role: .cancel) {
                connectionPendingDeletion = nil
            }
        }
    }

    private func savedConnectionRow(_ profile: ConnectionProfile) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.loadForEditing(profile)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.body)
                    Text("\(profile.username)@\(profile.host):\(profile.port)/\(profile.database ?? "tüm veritabanları")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = profile.note, !note.isEmpty {
                        Text(note)
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                connectionPendingDeletion = profile
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Bağlantıyı sil")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(viewModel.editingProfileId == profile.id ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Yeni MySQL Bağlantısı")
                .font(.title2.bold())

            // Each field's on-screen name is an external label, not the
            // `TextField`'s own title — with the border's `.plain` style, a
            // `TextField`'s title renders as placeholder text *inside* the
            // box; the field's own title is reserved for a real placeholder
            // hint (shows only while the field is empty).
            //
            // A `Grid` rather than `Form`/`LabeledContent`: `Form` only
            // shares one label-column width across rows for controls it
            // recognizes natively, so with these custom bordered fields
            // every row's label was self-sized and the borders started at
            // different x positions. `Grid` sizes the label column to its
            // widest cell by construction — every border's left edge lines
            // up exactly, with no hardcoded label width to go stale.
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                formRow("Bağlantı Adı") {
                    TextField("Opsiyonel", text: $viewModel.name)
                        .visibleFieldBorder()
                }
                formRow("Sunucu") {
                    TextField("", text: $viewModel.host)
                        .visibleFieldBorder()
                }
                formRow("Port") {
                    TextField("", text: $viewModel.port)
                        .visibleFieldBorder()
                }
                formRow("Kullanıcı Adı") {
                    TextField("", text: $viewModel.username)
                        .visibleFieldBorder()
                }
                formRow("Şifre") {
                    HStack(spacing: 10) {
                        RevealablePasswordField(text: $viewModel.password)
                        Toggle("Şifreyi sakla", isOn: $viewModel.savePassword)
                            .toggleStyle(.checkbox)
                            .font(.callout)
                    }
                }
                formRow("Veritabanı") {
                    TextField("Opsiyonel — boşsa tümü listelenir", text: $viewModel.database)
                        .visibleFieldBorder()
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .gridLineColor)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Not")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $viewModel.note)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .gridLineColor)))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button {
                    Task {
                        if let session = await viewModel.connect() {
                            appState.activeSession = session
                        }
                    }
                } label: {
                    if viewModel.isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Bağlan")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSubmit)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// One `Grid` row: right-aligned label in the shared label column,
    /// leading-aligned (and horizontally greedy) field in the second.
    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .gridColumnAlignment(.trailing)
                .lineLimit(1)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A `SecureField` with an eye-icon toggle to reveal the typed password as
/// plain text. AppKit/SwiftUI have no built-in "show password" control, so
/// this swaps between a `SecureField` and a `TextField` bound to the same
/// text depending on `isRevealed`.
private struct RevealablePasswordField: View {
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField("Şifre", text: $text)
                } else {
                    SecureField("Şifre", text: $text)
                }
            }
            .visibleFieldBorder()

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isRevealed ? "Şifreyi gizle" : "Şifreyi göster")
        }
    }
}
