import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../strings.dart';

/// First login only (`user.name == null`): `PATCH /me {name}`.
class NamePage extends ConsumerStatefulWidget {
  const NamePage({super.key});

  @override
  ConsumerState<NamePage> createState() => _NamePageState();
}

class _NamePageState extends ConsumerState<NamePage> {
  final _name = TextEditingController();
  String? _fieldError;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _fieldError = l10n.nameRequired);
      return;
    }
    setState(() {
      _fieldError = null;
      _error = null;
      _loading = true;
    });
    try {
      final user = await ref.read(meApiProvider).update(name: name);
      ref.read(sessionProvider.notifier).setUser(user);
    } catch (e) {
      if (mounted) setState(() => _error = l10n.common.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      appName: l10n.appTitle,
      tagline: l10n.appTagline,
      title: l10n.nameTitle,
      subtitle: l10n.nameSubtitle,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: InputDecoration(labelText: l10n.nameLabel, errorText: _fieldError, counterText: ''),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: 24),
        PrimaryButton(label: l10n.continueLabel, loading: _loading, onPressed: _submit),
      ],
    );
  }
}
