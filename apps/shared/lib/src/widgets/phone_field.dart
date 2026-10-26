import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 10-digit Indian mobile input with a fixed +91 prefix.
/// Validate with `IndianPhone.normalize`.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.enabled = true,
    this.autofocus = true,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      style: Theme.of(context).textTheme.titleLarge,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 10),
          child: Text('+91', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      onSubmitted: onSubmitted,
      onChanged: onChanged,
    );
  }
}
