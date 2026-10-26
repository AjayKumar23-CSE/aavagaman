import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../strings.dart';

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Edit name and email (`PATCH /me`).
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _form = GlobalKey<FormState>();
  late final User? _user = ref.read(sessionProvider.notifier).user;
  late final _name = TextEditingController(text: _user?.name ?? '');
  late final _emailCtl = TextEditingController(text: _user?.email ?? '');
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailCtl.text.trim();
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      // The API cannot clear an email (null is ignored), so an empty field
      // leaves the stored one unchanged.
      final user = await ref
          .read(meApiProvider)
          .update(name: _name.text.trim(), email: email.isEmpty ? null : email);
      ref.read(sessionProvider.notifier).setUser(user);
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
    } catch (e) {
      if (mounted) setState(() => _error = l10n.common.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                initialValue: IndianPhone.format(_user?.phone ?? ''),
                enabled: false,
                decoration: InputDecoration(labelText: l10n.phoneReadOnly, counterText: ''),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.nameLabel, counterText: ''),
                validator: (v) => (v ?? '').trim().isEmpty ? l10n.nameRequired : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailCtl,
                keyboardType: TextInputType.emailAddress,
                maxLength: 120,
                decoration: InputDecoration(labelText: l10n.emailLabel, counterText: ''),
                validator: (v) {
                  final t = (v ?? '').trim();
                  return t.isEmpty || _email.hasMatch(t) ? null : l10n.invalidEmail;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 16),
              PrimaryButton(label: l10n.save, loading: _loading, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
