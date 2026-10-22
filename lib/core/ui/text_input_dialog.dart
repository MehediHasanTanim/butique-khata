import 'package:flutter/material.dart';

/// Small dialog with one text field. The controller lives in the dialog's own
/// state, so it is disposed only after the dialog is fully gone (disposing it
/// right after `showDialog` returns breaks the closing animation).
class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    this.initialText = '',
    this.hint,
    this.maxLines = 3,
    super.key,
  });

  final String title;
  final String confirmLabel;
  final String cancelLabel;
  final String initialText;
  final String? hint;
  final int maxLines;

  /// Returns the entered text, or null if cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required String cancelLabel,
    String initialText = '',
    String? hint,
  }) => showDialog<String>(
    context: context,
    builder: (_) => TextInputDialog(
      title: title,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      initialText: initialText,
      hint: hint,
    ),
  );

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('text-input-dialog-field'),
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          key: const ValueKey('text-input-dialog-ok'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
