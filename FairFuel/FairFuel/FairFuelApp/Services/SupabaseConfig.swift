import Foundation

// Single source of truth for Supabase project credentials.
// Both CloudKitService and AuthService import from here.
enum SupabaseConfig {
    static let projectURL = "https://pbhxyxmwdpbksgnrgzwr.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBiaHh5eG13ZHBia3NnbnJnendyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1MzgwNjcsImV4cCI6MjA5MjExNDA2N30.80LkKL8mKudMbYjYJ08yDMzTY0M7xaAPtFTj4Ivd_XA"
}
