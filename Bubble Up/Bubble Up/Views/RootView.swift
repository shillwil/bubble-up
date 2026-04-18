import SwiftUI

/// Root view that gates between authentication and the main app.
struct RootView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthService(keychainService: KeychainService()))
}
