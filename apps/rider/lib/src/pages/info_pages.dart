import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.helpIntro),
          ),
          ListTile(
            leading: const Icon(Icons.phone),
            title: Text(l10n.helpPhoneLabel),
            subtitle: SelectableText(l10n.helpPhone),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: Text(l10n.helpEmailLabel),
            subtitle: SelectableText(l10n.helpEmail),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.helpHours, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(l10n.privacyBody),
      ),
    );
  }
}
