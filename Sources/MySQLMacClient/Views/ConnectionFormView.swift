import SwiftUI

struct ConnectionFormView: View {
    @ObservedObject var connectionStore: ConnectionStore
    @ObservedObject var appState: AppState
    @StateObject private var viewModel: ConnectionFormViewModel

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
                    Button {
                        Task {
                            if let session = await viewModel.connect(using: profile) {
                                appState.activeSession = session
                            }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(profile.name).font(.body)
                            Text("\(profile.username)@\(profile.host):\(profile.port)/\(profile.database ?? "tüm veritabanları")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Yeni MySQL Bağlantısı")
                .font(.title2.bold())

            Form {
                TextField("Bağlantı adı (opsiyonel)", text: $viewModel.name)
                TextField("Sunucu", text: $viewModel.host)
                TextField("Port", text: $viewModel.port)
                TextField("Kullanıcı adı", text: $viewModel.username)
                SecureField("Şifre", text: $viewModel.password)
                TextField("Veritabanı (opsiyonel — boşsa tümü listelenir)", text: $viewModel.database)
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
}
