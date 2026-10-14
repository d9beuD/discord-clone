import SwiftUI

struct LoginView: View {
    @Environment(AppViewModel.self) private var model
    @State private var identifier = ""
    @State private var password = ""

    var body: some View {
        HStack(spacing: 72) {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Un espace pour\nvos conversations.")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .tracking(-1)
                Text("Vos communautés, vos idées et vos échanges.\nUne expérience pensée pour votre Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                Label("SwiftUI + Rust", systemImage: "desktopcomputer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            }
            .frame(maxWidth: 390, alignment: .leading)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bienvenue").font(.title.bold())
                    Text("Retrouvez votre communauté.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("Identifiant") {
                        TextField("vous@exemple.fr", text: $identifier)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("login.identifier")
                    }
                    LabeledContent("Mot de passe") {
                        SecureField("Mot de passe", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("login.password")
                    }
                }
                .labelsHidden()
                Button("Se connecter") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                    .frame(maxWidth: .infinity)
                    .help("La connexion sera disponible lorsque le backend sera connecté.")
                Text("La connexion sera disponible avec le backend. Vos identifiants ne sont ni transmis ni enregistrés.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
                Button {
                    identifier = ""
                    password = ""
                    Task { await model.openDemo() }
                } label: {
                    HStack {
                        if model.isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "play.circle") }
                        Text("Ouvrir la démo")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .controlSize(.large)
                .disabled(model.isLoading)
                .accessibilityIdentifier("login.demo")
                Text("Explorez l’application avec des conversations locales.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red)
                        .accessibilityIdentifier("login.error")
                }
            }
            .padding(32)
            .frame(width: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.separator.opacity(0.5)))
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
