import SwiftUI

struct AvatarView: View {
    let user: User
    var size: CGFloat = 36

    private var color: Color {
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .blue]
        let index = user.id.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
        return colors[index]
    }

    var body: some View {
        Text(user.initials)
            .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}
