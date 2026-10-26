import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../strings.dart';
import 'registration_page.dart' show vehicleTypeLabel;

/// Read-only profile + vehicle, with a link to documents. Changes after
/// approval go through support (the API returns 409 ALREADY_REGISTERED).
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = ref.watch(driverProfileProvider).value;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final v = p.vehicle;

    Widget card(String title, List<Widget> rows) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          SoftCard(
            shadow: false,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(children: rows),
          ),
        ],
      ),
    );
    Widget row(String label, String? value) => KeyValueRow(label: label, value: value ?? '—');

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                InitialsAvatar(name: p.name, radius: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name ?? '', style: text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(IndianPhone.format(p.phone), style: text.bodyMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          StatusPill(
                            label: l10n.verification(p.verificationStatus),
                            color: p.verificationStatus == VerificationStatus.approved
                                ? AppColors.of(context).success
                                : p.verificationStatus == VerificationStatus.pending
                                ? AppColors.of(context).accent
                                : Theme.of(context).colorScheme.error,
                          ),
                          if (p.ratingAvg != null)
                            StatusPill(
                              label: p.ratingAvg!.toStringAsFixed(1),
                              color: AppColors.of(context).accent,
                              icon: Icons.star_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          card(l10n.sectionDriver, [
            row(l10n.licenceNoLabel, p.licenceNo),
            row(l10n.licenceExpiryLabel, p.licenceExpiry == null ? null : formatDate(p.licenceExpiry!)),
            row(l10n.dateOfBirthLabel, p.dateOfBirth == null ? null : formatDate(p.dateOfBirth!)),
          ]),
          card(
            l10n.sectionVehicle,
            v == null
                ? [ListTile(title: Text(l10n.profileNoVehicle))]
                : [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Align(alignment: Alignment.centerLeft, child: PlateBadge(v.regNumber, large: true)),
                    ),
                    row(
                      l10n.vehicleTypeLabel,
                      VehicleType.tryParse(v.vehicleType) == null ? v.vehicleType : vehicleTypeLabel(l10n, VehicleType.parse(v.vehicleType)),
                    ),
                    row('${l10n.makeLabel} / ${l10n.modelLabel}', '${v.make} ${v.model}'),
                    row(l10n.colourLabel, v.colour),
                    row(l10n.fuelLabel, v.fuelType == null ? null : l10n.fuel(v.fuelType!)),
                  ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SoftCard(
              shadow: false,
              padding: EdgeInsets.zero,
              onTap: () => context.push(Routes.documents),
              child: ListTile(
                leading: const IconBadge(icon: Icons.folder_open_rounded, size: 36),
                title: Text(l10n.profileDocuments),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
