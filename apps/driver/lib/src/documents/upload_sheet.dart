import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../strings.dart';
import '../widgets.dart';
import 'document_images.dart';

Future<void> showDocumentUploadSheet(BuildContext context, DocType type) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final uploaded = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DocumentUploadSheet(type: type),
  );
  if (uploaded ?? false) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.uploadDone)));
  }
}

enum _Phase { idle, preparing, uploading }

/// Pick (camera/gallery) → compress ≤ 800 KB JPEG → presign → PUT →
/// `POST /driver/documents`, with progress and retry of the failed step.
class DocumentUploadSheet extends ConsumerStatefulWidget {
  const DocumentUploadSheet({super.key, required this.type});

  final DocType type;

  @override
  ConsumerState<DocumentUploadSheet> createState() => _DocumentUploadSheetState();
}

class _DocumentUploadSheetState extends ConsumerState<DocumentUploadSheet> {
  final _form = GlobalKey<FormState>();
  final _last4 = TextEditingController();
  Uint8List? _bytes;
  DateTime? _expiry;
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String? _error;

  /// File already stored by a previous attempt; a retry only re-registers it.
  String? _uploadedKey;

  DocType get type => widget.type;

  @override
  void dispose() {
    _last4.dispose();
    super.dispose();
  }

  Future<void> _pick(PhotoSource source) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error = null;
      _phase = _Phase.preparing;
    });
    try {
      final bytes = await ref.read(documentImageServiceProvider).pick(source, frontCamera: type == DocType.selfie);
      if (!mounted) return;
      setState(() {
        if (bytes != null) {
          _bytes = bytes;
          _uploadedKey = null;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = l10n.uploadPhotoError);
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context);
    if (_bytes == null) {
      setState(() => _error = l10n.uploadPickFirst);
      return;
    }
    if (!_form.currentState!.validate()) return;
    final api = ref.read(driverApiProvider);
    setState(() {
      _error = null;
      _phase = _Phase.uploading;
      _progress = 0;
    });
    try {
      var key = _uploadedKey;
      if (key == null) {
        final presigned = await api.presign(type);
        setState(() => _progress = 0.05);
        await api.putObject(
          presigned.uploadUrl,
          _bytes!,
          onProgress: (sent, total) {
            if (mounted && total > 0) setState(() => _progress = 0.05 + 0.9 * sent / total);
          },
        );
        key = _uploadedKey = presigned.fileKey;
      }
      await api.createDocument(
        type,
        key,
        expiry: type.requiresExpiry ? _expiry : null,
        idLast4: type.requiresIdLast4 ? _last4.text : null,
      );
      if (mounted) setState(() => _progress = 1);
      try {
        await ref.read(driverProfileProvider.notifier).refresh();
      } catch (_) {
        // The document is saved; the list refreshes on the next pull.
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = l10n.common.errorMessage(e);
          _phase = _Phase.idle;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final busy = _phase != _Phase.idle;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.uploadTitle(l10n.docType(type)), style: text.titleLarge),
              const SizedBox(height: 8),
              Text(type == DocType.selfie ? l10n.uploadHintSelfie : l10n.uploadHintDocument),
              const SizedBox(height: 16),
              if (_bytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_bytes!, height: 180, fit: BoxFit.contain),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _pick(PhotoSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: Text(l10n.uploadCamera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _pick(PhotoSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: Text(l10n.uploadGallery),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (type.requiresExpiry)
                DateField(label: l10n.uploadExpiryLabel, value: _expiry, onChanged: (d) => setState(() => _expiry = d)),
              if (type.requiresIdLast4)
                TextFormField(
                  controller: _last4,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: l10n.uploadIdLast4Label, helperText: l10n.uploadIdLast4Help),
                  validator: (v) => RegExp(r'^\d{4}$').hasMatch(v ?? '') ? null : l10n.uploadIdLast4Invalid,
                ),
              if (_phase == _Phase.preparing) ...[
                Text(l10n.uploadPreparing),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (_phase == _Phase.uploading) ...[
                Text(l10n.uploadSending),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress),
              ],
              if (_error != null) ...[const SizedBox(height: 8), ErrorBanner(message: _error!)],
              const SizedBox(height: 16),
              PrimaryButton(
                label: _error != null && _bytes != null ? l10n.uploadRetry : l10n.uploadButton,
                loading: _phase == _Phase.uploading,
                onPressed: _phase == _Phase.preparing ? null : _upload,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
