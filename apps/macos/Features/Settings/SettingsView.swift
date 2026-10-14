import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) private var model
    @AppStorage("appearance", store: AppPreferences.store) private var appearance = "system"

    var body: some View {
        Form {
            Section("Apparence") {
                Picker("Thème", selection: $appearance) {
                    Text("Système").tag("system")
                    Text("Clair").tag("light")
                    Text("Sombre").tag("dark")
                }
                .accessibilityIdentifier("settings.appearance")
            }
            Section("Compte") {
                LabeledContent("Profil", value: model.currentUser?.displayName ?? "Non connecté")
                LabeledContent("Session", value: model.isDemoOpen ? "Démonstration locale" : "Aucune")
                if model.isDemoOpen {
                    Button("Fermer la session démo", role: .destructive) { model.closeSession() }
                        .accessibilityIdentifier("settings.logout")
                }
            }
            Section("À propos") {
                LabeledContent("Application", value: "Discord Clone · 0.1.0")
                Text("Interface native macOS · cœur Rust\nLes conversations de démonstration restent en mémoire et sont réinitialisées à la fermeture de la session.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 380)
    }
}
