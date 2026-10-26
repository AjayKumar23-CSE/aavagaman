import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../strings.dart';
import '../widgets.dart';

final _stripSpaces = RegExp(r'[\s-]');
final _licenceNo = RegExp(r'^[A-Z0-9]{8,20}$');
final _regNumber = RegExp(r'^[A-Z0-9]{6,11}$');

/// Mirrors the backend's DTO transform: strip spaces/dashes, upper-case.
String normaliseCode(String input) => input.replaceAll(_stripSpaces, '').toUpperCase();

/// `POST /driver/register` — profile + vehicle. Shown for new drivers and
/// after a rejection (prefilled from `GET /driver/me`).
class RegistrationPage extends ConsumerStatefulWidget {
  const RegistrationPage({super.key});

  @override
  ConsumerState<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends ConsumerState<RegistrationPage> {
  final _form = GlobalKey<FormState>();
  late final DriverProfile? _initial = ref.read(driverProfileProvider).value;
  late final _name = TextEditingController(text: _initial?.name ?? '');
  late final _licence = TextEditingController(text: _initial?.licenceNo ?? '');
  late final _reg = TextEditingController(text: _initial?.vehicle?.regNumber ?? '');
  late final _make = TextEditingController(text: _initial?.vehicle?.make ?? '');
  late final _model = TextEditingController(text: _initial?.vehicle?.model ?? '');
  late final _colour = TextEditingController(text: _initial?.vehicle?.colour ?? '');
  late DateTime? _expiry = _initial?.licenceExpiry;
  late DateTime? _dob = _initial?.dateOfBirth;
  late FuelType? _fuel = _initial?.vehicle?.fuelType;
  late VehicleType _vehicleType = VehicleType.tryParse(_initial?.vehicle?.vehicleType) ?? VehicleType.sedan;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_name, _licence, _reg, _make, _model, _colour]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final profile = await ref
          .read(driverApiProvider)
          .register(
            DriverRegistration(
              name: _name.text.trim(),
              licenceNo: normaliseCode(_licence.text),
              licenceExpiry: _expiry!,
              dateOfBirth: _dob!,
              vehicle: VehicleInput(
                regNumber: normaliseCode(_reg.text),
                make: _make.text.trim(),
                model: _model.text.trim(),
                colour: _colour.text.trim(),
                fuelType: _fuel!,
                vehicleType: _vehicleType,
              ),
            ),
          );
      ref.read(driverProfileProvider.notifier).set(profile);
      if (mounted) context.go(gateFor(profile));
    } catch (e) {
      if (mounted) setState(() => _error = l10n.common.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final rejected = _initial?.verificationStatus == VerificationStatus.rejected;
    String? required(String? v) => (v ?? '').trim().isEmpty ? l10n.fieldRequired : null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.registerTitle), actions: const [LogoutButton()]),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(rejected ? l10n.registerRejected : l10n.registerIntro),
              if (rejected && _initial?.reviewerNote != null) ...[
                const SizedBox(height: 8),
                NoteBanner(text: l10n.reviewerNoteLabel(_initial!.reviewerNote!)),
              ],
              const SizedBox(height: 16),
              Text(l10n.sectionDriver, style: text.titleMedium),
              const SizedBox(height: 8),
              TextFormField(
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.nameLabel, counterText: ''),
                validator: required,
              ),
              TextFormField(
                controller: _licence,
                maxLength: 24,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: l10n.licenceNoLabel, counterText: ''),
                validator: (v) =>
                    required(v) ?? (_licenceNo.hasMatch(normaliseCode(v!)) ? null : l10n.invalidLicenceNo),
              ),
              DateField(label: l10n.licenceExpiryLabel, value: _expiry, onChanged: (d) => setState(() => _expiry = d)),
              BirthDateField(
                key: const Key('date-of-birth'),
                label: l10n.dateOfBirthLabel,
                value: _dob,
                onChanged: (d) => setState(() => _dob = d),
              ),
              const SizedBox(height: 24),
              Text(l10n.sectionVehicle, style: text.titleMedium),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: InputDecoration(labelText: l10n.vehicleTypeLabel, border: InputBorder.none),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final t in VehicleType.values)
                      ChoiceChip(
                        key: Key('vehicle-type-${t.wire}'),
                        avatar: Icon(t.icon, size: 18),
                        label: Text(vehicleTypeLabel(l10n, t)),
                        selected: _vehicleType == t,
                        onSelected: (_) => setState(() => _vehicleType = t),
                      ),
                  ],
                ),
              ),
              TextFormField(
                controller: _reg,
                maxLength: 14,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: l10n.regNumberLabel, hintText: l10n.regNumberHint, counterText: ''),
                validator: (v) =>
                    required(v) ?? (_regNumber.hasMatch(normaliseCode(v!)) ? null : l10n.invalidRegNumber),
              ),
              TextFormField(
                controller: _make,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.makeLabel, hintText: l10n.makeHint, counterText: ''),
                validator: required,
              ),
              TextFormField(
                controller: _model,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.modelLabel, hintText: l10n.modelHint, counterText: ''),
                validator: required,
              ),
              TextFormField(
                controller: _colour,
                maxLength: 30,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.colourLabel, counterText: ''),
                validator: required,
              ),
              FormField<FuelType>(
                initialValue: _fuel,
                validator: (_) => _fuel == null ? l10n.fieldRequired : null,
                builder: (field) => InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.fuelLabel,
                    errorText: field.errorText,
                    border: InputBorder.none,
                  ),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final f in FuelType.values)
                        ChoiceChip(
                          label: Text(l10n.fuel(f)),
                          selected: _fuel == f,
                          onSelected: (_) {
                            setState(() => _fuel = f);
                            field.didChange(f);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 8), ErrorBanner(message: _error!)],
              const SizedBox(height: 16),
              PrimaryButton(label: l10n.submit, loading: _loading, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vehicle class names (D-056).
String vehicleTypeLabel(AppLocalizations l10n, VehicleType t) => switch (t) {
      VehicleType.bike => l10n.vehicleBike,
      VehicleType.auto => l10n.vehicleAuto,
      VehicleType.mini => l10n.vehicleMini,
      VehicleType.sedan => l10n.vehicleSedan,
    };
