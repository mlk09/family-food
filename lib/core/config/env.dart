/// Build-time configuration.
///
/// Values are injected with `--dart-define-from-file=.env` (see `.env.example`).
/// Only PUBLIC values belong here. The Supabase anon key is designed to be
/// public and is protected by Row Level Security. Never put the OpenAI key or
/// the Supabase service-role key in the app — they live in Edge Function secrets.
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Name of the Supabase Edge Function that proxies AI requests.
  static const aiFunctionName =
      String.fromEnvironment('AI_FUNCTION_NAME', defaultValue: 'chef-ai');

  /// Deep link used for OAuth (Google) and password-reset redirects.
  static const authRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
    defaultValue: 'familyfood://login-callback',
  );

  /// Set to "true" to show the Google sign-in button (requires provider setup).
  static const googleSignInEnabled =
      bool.fromEnvironment('GOOGLE_SIGN_IN_ENABLED', defaultValue: false);

  static bool get isSupabaseConfigured =>
      supabaseUrl.startsWith('https://') &&
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('YOUR_PROJECT');
}
