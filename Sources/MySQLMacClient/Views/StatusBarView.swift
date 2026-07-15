import SwiftUI

struct StatusBarView: View {
    let profile: ConnectionProfile
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            Text("\(profile.username)@\(profile.host):\(profile.port)\(profile.database.map { "/\($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Bağlantıyı Kes", action: onDisconnect)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
