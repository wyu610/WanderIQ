import Foundation

/// Reads the public Supabase client credentials injected via Supabase.xcconfig
/// → Info.plist. Fatal-errors early in DEBUG if missing so misconfig is obvious.
enum SupabaseConfig {
    static var url: URL {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let u = URL(string: s), !s.isEmpty else {
            fatalError("SUPABASE_URL missing — copy Supabase.xcconfig.example to Supabase.xcconfig")
        }
        return u
    }
    static var anonKey: String {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !k.isEmpty else {
            fatalError("SUPABASE_ANON_KEY missing — copy Supabase.xcconfig.example to Supabase.xcconfig")
        }
        return k
    }
}
