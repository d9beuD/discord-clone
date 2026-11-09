import SwiftUI

struct LoginView: View {
    @Environment(AppViewModel.self) private var model
    @State private var identifier = ""
    @State private var password = ""
    @State private var username = ""
    @State private var creatingAccount = false
    @State private var baseURL = "http://localhost:3000"

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
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
                        Picker("Compte", selection: $creatingAccount) {
                            Text("Connexion").tag(false)
                            Text("Créer un compte").tag(true)
                        }
                        .pickerStyle(.segmented)
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("Adresse du serveur", text: $baseURL)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Adresse du backend")
                                .accessibilityIdentifier("login.backend")
                            if creatingAccount {
                                TextField("Nom d’utilisateur", text: $username)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Nom d’utilisateur")
                                    .accessibilityIdentifier("login.username")
                            }
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
                        Button(creatingAccount ? "Créer mon compte" : "Se connecter") {
                            let secret = password
                            password = ""
                            Task { await model.authenticate(baseURL: baseURL, email: identifier, password: secret,
                                username: creatingAccount ? username : nil) }
                        }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.isLoading || identifier.isEmpty || password.isEmpty || (creatingAccount && username.isEmpty))
                            .accessibilityIdentifier("login.submit")
                            .keyboardShortcut(.defaultAction)
                            .frame(maxWidth: .infinity)

                        Text(creatingAccount ? "Mot de passe de 15 à 128 caractères. La session reste en mémoire sur ce Mac." : "Connectez-vous au backend. La session reste en mémoire sur ce Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if model.isLoading { ProgressView("Connexion…").controlSize(.small) }
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
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
