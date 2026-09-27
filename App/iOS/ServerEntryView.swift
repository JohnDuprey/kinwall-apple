import SwiftUI
import KinwallKit

/// First launch: where is the family's Kinwall? Checks the address answers like a Kinwall server
/// (GET /api/health) before handing it to the web view.
struct ServerEntryView: View {
    let onConnect: (URL) -> Void
    @State private var address = ""
    @State private var checking = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Welcome to Kinwall").font(.largeTitle.bold())
                Text("Enter your family's Kinwall address. For hosted Kinwall, your family name is enough.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true) // wrap, don't truncate, when the keyboard is up
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("ourfamily or kinwall.example.com", text: $address)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(connect)
                    .padding(14)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 14))
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            }
            Button(action: connect) {
                Group { if checking { ProgressView() } else { Text("Connect") } }
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || checking)
            Spacer()
            Text("You'll pair this device on the next screen. An admin approves it in Kinwall under Settings → Access → Displays.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .onAppear { focused = true }
    }

    private func connect() {
        guard let url = ServerAddress.normalize(address) else { problem = "That doesn't look like a web address."; return }
        checking = true; problem = nil
        Task {
            defer { checking = false }
            do {
                var req = URLRequest(url: url.appending(path: "api/health"), timeoutInterval: 10)
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                let (_, response) = try await URLSession.shared.data(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    problem = "\(url.host() ?? "That address") answered, but it isn't a Kinwall server."
                    return
                }
                onConnect(url)
            } catch {
                problem = "Couldn't reach \(url.host() ?? "that address"). Check the address and your connection."
            }
        }
    }
}
