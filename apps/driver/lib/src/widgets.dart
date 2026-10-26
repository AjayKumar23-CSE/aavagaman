import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../l10n/app_localizations.dart';
import 'router.dart';
import 'strings.dart';

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Date form field backed by the Material date picker. Past dates are
/// rejected (the API returns 422 LICENCE_EXPIRED / DOCUMENT_EXPIRED).
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FormField<DateTime>(
      initialValue: value,
      validator: (_) {
        if (value == null) return l10n.fieldRequired;
        final v = DateTime(value!.year, value!.month, value!.day);
        return v.isBefore(_today()) ? l10n.dateExpired : null;
      },
      builder: (field) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () async {
            final today = _today();
            final initial = value != null && !value!.isBefore(today)
                ? DateTime(value!.year, value!.month, value!.day)
                : DateTime(today.year + 1, today.month, today.day);
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: today,
              lastDate: DateTime(today.year + 30),
              helpText: label,
            );
            if (picked != null) {
              onChanged(picked);
              field.didChange(picked);
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              errorText: field.errorText,
              floatingLabelStyle: Theme.of(context).textTheme.labelMedium,
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            child: Text(value == null ? l10n.selectDate : formatDate(value!)),
          ),
        ),
      ),
    );
  }
}

/// Minimum driver age (the server answers 422 `DATE_OF_BIRTH_INVALID` too).
const minDriverAge = 18;

/// Date of birth, picked from the past; must be at least [minDriverAge] years ago.
class BirthDateField extends StatelessWidget {
  const BirthDateField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  static DateTime latestAllowed([DateTime? now]) {
    final t = now ?? _today();
    return DateTime(t.year - minDriverAge, t.month, t.day);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final latest = latestAllowed();
    return FormField<DateTime>(
      initialValue: value,
      validator: (_) {
        if (value == null) return l10n.fieldRequired;
        final v = DateTime(value!.year, value!.month, value!.day);
        return v.isAfter(latest) ? l10n.dateOfBirthTooYoung : null;
      },
      builder: (field) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () async {
            final initial = value != null && !value!.isAfter(latest)
                ? DateTime(value!.year, value!.month, value!.day)
                : DateTime(latest.year - 7, latest.month, latest.day);
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1940),
              lastDate: latest,
              initialEntryMode: DatePickerEntryMode.input,
              helpText: label,
            );
            if (picked != null) {
              onChanged(picked);
              field.didChange(picked);
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              errorText: field.errorText,
              floatingLabelStyle: Theme.of(context).textTheme.labelMedium,
              suffixIcon: const Icon(Icons.cake_outlined),
            ),
            child: Text(value == null ? l10n.selectDate : formatDate(value!)),
          ),
        ),
      ),
    );
  }
}

/// Reviewer note / warning box.
class NoteBanner extends StatelessWidget {
  const NoteBanner({super.key, required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InfoBanner(message: text, tone: BannerTone.warning, icon: icon);
  }
}

Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.logoutConfirmTitle),
      content: Text(l10n.logoutConfirmBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.menuLogout)),
      ],
    ),
  );
  if (ok ?? false) await ref.read(sessionProvider.notifier).logout();
}

class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: AppLocalizations.of(context).menuLogout,
    icon: const Icon(Icons.logout),
    onPressed: () => confirmLogout(context, ref),
  );
}

class DriverDrawer extends ConsumerWidget {
  const DriverDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user : null));
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    void open(String route) {
      Navigator.of(context).pop();
      context.push(route);
    }

    Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
      leading: Icon(icon, color: scheme.onSurface),
      title: Text(label, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: BoxDecoration(gradient: colors.gradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Row(
                  children: [
                    InitialsAvatar(name: user?.name, radius: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? '',
                            style: text.titleLarge?.copyWith(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            IndianPhone.format(user?.phone ?? ''),
                            style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          item(Icons.account_balance_wallet_rounded, l10n.menuEarnings, () => open(Routes.earnings)),
          item(Icons.history_rounded, l10n.menuHistory, () => open(Routes.history)),
          item(Icons.badge_outlined, l10n.menuProfile, () => open(Routes.profile)),
          item(Icons.support_agent_rounded, l10n.menuHelp, () => open(Routes.help)),
          item(Icons.privacy_tip_outlined, l10n.menuPrivacy, () => open(Routes.privacy)),
          item(Icons.battery_saver_rounded, l10n.homeBatteryMenu, () => open(Routes.battery)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Divider()),
          // The dialog opens over the drawer; on logout the router leaves.
          item(Icons.logout_rounded, l10n.menuLogout, () => confirmLogout(context, ref)),
        ],
      ),
    );
  }
}
