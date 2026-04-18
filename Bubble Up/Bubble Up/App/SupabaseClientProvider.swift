import Foundation
import Supabase

/// Single shared Supabase client for the entire app.
/// AuthService, SupabaseSummaryProvider, and all other consumers use this same instance
/// so the authenticated session is shared and persisted.
enum SupabaseClientProvider {
    static let shared = SupabaseClient(
        supabaseURL: Config.supabaseURL,
        supabaseKey: Config.supabaseAnonKey
    )
}
