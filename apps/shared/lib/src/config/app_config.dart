/// Build-time configuration, set with `--dart-define=KEY=value`.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.sentryDsn = '',
    this.environment = 'dev',
    this.googleMapsApiKey = '',
  });

  /// Reads `--dart-define` values. The default API URL targets the Android
  /// emulator's view of the host machine (`10.0.2.2`).
  factory AppConfig.fromEnvironment() => const AppConfig(
        apiBaseUrl: String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://10.0.2.2:3000',
        ),
        sentryDsn: String.fromEnvironment('SENTRY_DSN'),
        environment: String.fromEnvironment('APP_ENV', defaultValue: 'dev'),
        googleMapsApiKey: String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
      );

  final String apiBaseUrl;

  /// Sentry is skipped when empty.
  final String sentryDsn;

  /// `dev` or `prod` (SPEC §17.5), reported to Sentry.
  final String environment;

  /// Google Places API (New) key; the Maps SDK key is injected through the
  /// Android manifest instead (`MAPS_API_KEY` Gradle placeholder). Empty →
  /// Places search is disabled and the user types an address or picks a
  /// point on the map.
  final String googleMapsApiKey;

  /// REST routes live under /v1 (SPEC §7).
  String get restBaseUrl => '$apiBaseUrl/v1';

  /// Socket.io namespace URL (SPEC §8).
  String get realtimeUrl => '$apiBaseUrl/rt';

  /// Public "track my ride" page for a ride's `share_token` (SPEC §7.2
  /// `GET /share/:token`; serves HTML to browsers, JSON to `Accept: application/json`).
  String shareUrl(String shareToken) => '$apiBaseUrl/v1/share/$shareToken';
}
