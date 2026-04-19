import Foundation

enum Config {
    // MARK: - Supabase

    /// Supabase project URL.
    static let supabaseURL = URL(string: "https://pbbjraufpmczhhwvryds.supabase.co")!

    /// Supabase anonymous key — safe for client use, access controlled by RLS.
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBiYmpyYXVmcG1jemhod3ZyeWRzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0Njg5ODgsImV4cCI6MjA5MjA0NDk4OH0.0K09GrbU924Jv4Vl9fVuocERJd-sLl8uIpR50GtyEUQ"

    // MARK: - App Group

    static let appGroupIdentifier = "group.com.shillwil.bubble-up"

    // MARK: - AI Defaults

    /// Default AI model for link summaries (F&F users via Edge Functions).
    static let defaultLinkSummaryModel = "gemini-3.1-flash"

    /// Default AI model for book summaries (F&F users via Edge Functions).
    static let defaultBookSummaryModel = "claude-sonnet-4-6"

    // MARK: - Request Scheduler

    static let maxConcurrentRequests = 3
    static let maxRetryAttempts: Int16 = 8
    static let maxBackoffSeconds: TimeInterval = 300 // 5 minutes

    // MARK: - Rate Limits (F&F)

    static let defaultDailyLimit = 20
    static let defaultMonthlyLimit = 200
}
