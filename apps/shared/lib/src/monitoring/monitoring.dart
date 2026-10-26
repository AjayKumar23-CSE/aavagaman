import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';

/// Starts the app, with Sentry when `--dart-define=SENTRY_DSN=...` is set.
Future<void> bootstrap(AppConfig config, Widget Function() app) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (config.sentryDsn.isEmpty) {
    runApp(app());
    return;
  }
  await SentryFlutter.init(
    (o) {
      o.dsn = config.sentryDsn;
      o.environment = config.environment;
      o.sendDefaultPii = false;
      o.beforeSend = scrubSentryEvent;
      o.beforeBreadcrumb = (crumb, hint) => crumb == null ? null : scrubBreadcrumb(crumb);
    },
    appRunner: () => runApp(app()),
  );
}

final _sensitiveKey = RegExp(
  r'phone|token|authorization|password|secret|otp|cookie|last4|fcm|^code$',
  caseSensitive: false,
);
final _phone = RegExp(r'(?<![\d+])(\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}(?!\d)');
final _jwt = RegExp(r'eyJ[\w-]+\.[\w-]+\.[\w-]+');
final _bearer = RegExp(r'Bearer\s+\S+', caseSensitive: false);

const _filtered = '[Filtered]';

/// Masks phone numbers and tokens in free text.
String scrubText(String input) => input
    .replaceAll(_jwt, _filtered)
    .replaceAll(_bearer, 'Bearer $_filtered')
    .replaceAllMapped(_phone, (m) {
      final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
      return '******${digits.substring(digits.length - 4)}';
    });

/// Recursively drops sensitive keys and masks values (SPEC §16: Sentry
/// scrubs phone and token fields).
Object? scrubValue(Object? value, [String? key]) {
  if (key != null && _sensitiveKey.hasMatch(key)) return _filtered;
  return switch (value) {
    String s => scrubText(s),
    Map m => {for (final e in m.entries) e.key: scrubValue(e.value, e.key.toString())},
    List l => [for (final v in l) scrubValue(v)],
    _ => value,
  };
}

Map<String, dynamic>? _scrubMap(Map<String, dynamic>? m) =>
    m == null ? null : (scrubValue(m) as Map).cast<String, dynamic>();

Breadcrumb scrubBreadcrumb(Breadcrumb crumb) {
  if (crumb.message != null) crumb.message = scrubText(crumb.message!);
  crumb.data = _scrubMap(crumb.data);
  return crumb;
}

/// `beforeSend` hook: strips phone numbers, tokens and user PII.
FutureOr<SentryEvent?> scrubSentryEvent(SentryEvent event, Hint hint) {
  final user = event.user;
  event.user = user?.id == null ? null : SentryUser(id: user!.id);

  final msg = event.message;
  if (msg != null) {
    msg.formatted = scrubText(msg.formatted);
    msg.params = msg.params?.map((p) => p is String ? scrubText(p) : p).toList();
  }
  for (final ex in event.exceptions ?? const <SentryException>[]) {
    if (ex.value != null) ex.value = scrubText(ex.value!);
  }
  final req = event.request;
  if (req != null) {
    event.request = SentryRequest(
      url: req.url == null ? null : scrubText(req.url!),
      method: req.method,
      queryString: req.queryString == null ? null : scrubText(req.queryString!),
      fragment: req.fragment,
      data: scrubValue(req.data),
      headers: {
        for (final h in req.headers.entries)
          h.key: _sensitiveKey.hasMatch(h.key) ? _filtered : scrubText(h.value),
      },
    );
  }
  // ignore: deprecated_member_use
  event.extra = _scrubMap(event.extra);
  event.tags = event.tags?.map((k, v) => MapEntry(k, _sensitiveKey.hasMatch(k) ? _filtered : scrubText(v)));
  event.breadcrumbs = event.breadcrumbs?.map(scrubBreadcrumb).toList();
  return event;
}
