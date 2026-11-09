import Foundation

/// Proyecto de Supabase donde se sincronizan los datos.
/// La publishable key es pública por diseño (va dentro de la app): lo que protege los datos son las
/// políticas por usuario de `supabase/migrations`. Nunca pongas aquí la secret / service_role key.
enum SupabaseConfig {
    static let url = URL(string: "https://zktuqtpqiclbtxcwnitz.supabase.co")!
    static let publishableKey = "sb_publishable_qxvoq48xkja525js5bidyg_65mRcth7"
}
