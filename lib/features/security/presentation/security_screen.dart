import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/ui/app_list_tile.dart';
import 'package:tailor_khata/features/security/presentation/lock_controller.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Turn the PIN lock on and off and choose how it behaves (TD §6).
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool? _biometricsAvailable;

  @override
  void initState() {
    super.initState();
    ref.read(deviceAuthProvider).biometricsAvailable().then((value) {
      if (mounted) setState(() => _biometricsAvailable = value);
    });
  }

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _enable() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const PinSetupDialog(),
    );
    if (pin == null || !mounted) return;
    await ref.read(lockControllerProvider.notifier).setupPin(pin);
    if (mounted) _say(AppL10n.of(context).securityPinSaved);
  }

  /// Asks for the current PIN; true if it was right. Wrong tries count
  /// towards the lockout like on the lock screen.
  Future<bool> _confirmPin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const PinPromptDialog(),
    );
    if (pin == null || !mounted) return false;
    final result = await ref
        .read(lockControllerProvider.notifier)
        .verifyPin(pin);
    if (result != PinCheck.ok && mounted) {
      _say(AppL10n.of(context).lockWrongPin);
    }
    return result == PinCheck.ok;
  }

  Future<void> _change() async {
    if (!await _confirmPin() || !mounted) return;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const PinSetupDialog(),
    );
    if (pin == null || !mounted) return;
    await ref.read(lockControllerProvider.notifier).setupPin(pin);
    if (mounted) _say(AppL10n.of(context).securityPinSaved);
  }

  Future<void> _disable() async {
    final l10n = AppL10n.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.securityDisableTitle),
        content: Text(l10n.securityDisableBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: const ValueKey('security-disable-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.securityDisable),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (!await _confirmPin() || !mounted) return;
    await ref.read(lockControllerProvider.notifier).disable();
  }

  Future<void> _setBiometric(bool value) async {
    final controller = ref.read(lockControllerProvider.notifier);
    if (value) {
      // Make sure it really works before relying on it to open the app.
      final reason = AppL10n.of(context).lockBiometricReason;
      final ok = await ref
          .read(deviceAuthProvider)
          .authenticate(reason: reason, biometricOnly: true);
      if (!ok) return;
    }
    await controller.setBiometric(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(lockControllerProvider);
    final bangla = ref.watch(useBanglaDigitsProvider);

    String timeoutLabel(int seconds) => seconds == 0
        ? l10n.securityTimeoutNow
        : (() {
            final text = l10n.securityTimeoutMinutes(seconds ~/ 60);
            return bangla ? DigitFormatter.toBangla(text) : text;
          })();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.securityTitle)),
      body: ListView(
        children: [
          SwitchListTile(
            key: const ValueKey('security-enable'),
            title: Text(l10n.securityEnable),
            subtitle: Text(l10n.securitySubtitle),
            value: state.configured,
            onChanged: (on) => on ? _enable() : _disable(),
          ),
          if (state.configured) ...[
            AppListTile(
              key: const ValueKey('security-change'),
              title: l10n.securityChangePin,
              leading: const Icon(Icons.password),
              onTap: _change,
            ),
            SwitchListTile(
              key: const ValueKey('security-biometric'),
              title: Text(l10n.securityBiometric),
              subtitle: _biometricsAvailable == false
                  ? Text(l10n.securityBiometricUnavailable)
                  : null,
              value: state.biometric,
              onChanged: _biometricsAvailable == true ? _setBiometric : null,
            ),
            ListTile(
              title: Text(l10n.securityTimeout),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DropdownButton<int>(
                  key: const ValueKey('security-timeout'),
                  isExpanded: true,
                  value: LockController.timeouts.contains(state.timeoutSeconds)
                      ? state.timeoutSeconds
                      : LockController.timeouts[1],
                  items: [
                    for (final s in LockController.timeouts)
                      DropdownMenuItem(value: s, child: Text(timeoutLabel(s))),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(lockControllerProvider.notifier)
                          .setTimeout(value);
                    }
                  },
                ),
              ),
            ),
            AppListTile(
              key: const ValueKey('security-lock-now'),
              title: l10n.securityLockNow,
              leading: const Icon(Icons.lock_clock_outlined),
              onTap: () => ref.read(lockControllerProvider.notifier).lock(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Digits only, and Bangla digits typed on a Bangla keyboard count too.
class _PinFormatter extends TextInputFormatter {
  const _PinFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final latin = DigitFormatter.toLatin(newValue.text);
    final digits = latin.replaceAll(RegExp('[^0-9]'), '');
    final clipped = digits.length > 8 ? digits.substring(0, 8) : digits;
    return TextEditingValue(
      text: clipped,
      selection: TextSelection.collapsed(offset: clipped.length),
    );
  }
}

/// Choose a PIN and type it twice.
class PinSetupDialog extends StatefulWidget {
  const PinSetupDialog({super.key});

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AlertDialog(
      title: Text(l10n.securitySetPin),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('pin-field'),
              controller: _first,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [_PinFormatter()],
              decoration: InputDecoration(
                labelText: l10n.securitySetPin,
                helperText: l10n.securityPinHint,
              ),
              validator: (v) =>
                  (v ?? '').length < 4 ? l10n.securityPinShort : null,
            ),
            TextFormField(
              key: const ValueKey('pin-confirm'),
              controller: _second,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [_PinFormatter()],
              decoration: InputDecoration(labelText: l10n.securityConfirmPin),
              validator: (v) =>
                  v != _first.text ? l10n.securityPinMismatch : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('pin-save'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _first.text);
            }
          },
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}

/// Asks for the current PIN.
class PinPromptDialog extends StatefulWidget {
  const PinPromptDialog({super.key});

  @override
  State<PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<PinPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AlertDialog(
      title: Text(l10n.securityCurrentPin),
      content: TextField(
        key: const ValueKey('pin-current'),
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: const [_PinFormatter()],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('pin-current-ok'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.actionConfirm),
        ),
      ],
    );
  }
}
