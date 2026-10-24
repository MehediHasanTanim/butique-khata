import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/features/security/presentation/lock_controller.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Covers the app while it is locked and lets the PIN (or a fingerprint) in.
/// It has no router or dialog dependencies: it sits above the Navigator.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  static const int _maxLength = 8;

  String _pin = '';
  bool _wrong = false;
  bool _checking = false;
  bool _resetting = false;
  String? _resetError;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (ref.read(lockControllerProvider).lockedUntil != null) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _biometric() async {
    if (!mounted) return;
    final state = ref.read(lockControllerProvider);
    if (!state.biometric) return;
    final reason = AppL10n.of(context).lockBiometricReason;
    await ref
        .read(lockControllerProvider.notifier)
        .unlockWithBiometrics(reason);
  }

  void _press(String digit) {
    if (_checking || _pin.length >= _maxLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _wrong = false;
    });
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _wrong = false;
    });
  }

  Future<void> _submit() async {
    if (_pin.length < 4 || _checking) return;
    setState(() => _checking = true);
    final result = await ref
        .read(lockControllerProvider.notifier)
        .verifyPin(_pin);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _pin = '';
      _wrong = result != PinCheck.ok;
    });
  }

  Future<void> _reset() async {
    final l10n = AppL10n.of(context);
    final result = await ref
        .read(lockControllerProvider.notifier)
        .resetViaDeviceCredential(l10n.lockBiometricReason);
    if (!mounted) return;
    setState(() {
      _resetError = switch (result) {
        ResetResult.done => null,
        ResetResult.failed => l10n.lockResetFailed,
        ResetResult.noDeviceLock => l10n.lockResetNoDeviceLock,
      };
    });
  }

  String _remaining(Duration left, bool bangla) {
    final seconds = (left.inMilliseconds / 1000).ceil();
    final text =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return bangla ? DigitFormatter.toBangla(text) : text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(lockControllerProvider);
    final bangla = ref.watch(useBanglaDigitsProvider);
    final left = state.lockoutLeft(ref.read(clockProvider).now());
    final lockedOut = left > Duration.zero;

    return Scaffold(
      key: const ValueKey('lock-screen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.lockTitle,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (_resetting)
                    ..._resetPanel(l10n)
                  else ...[
                    Text(l10n.lockEnterPin, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    _Dots(count: _pin.length, error: _wrong),
                    SizedBox(
                      height: 40,
                      child: Center(
                        child: lockedOut
                            ? Text(
                                l10n.lockTryAgainIn(_remaining(left, bangla)),
                                key: const ValueKey('lock-lockout'),
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              )
                            : _wrong
                            ? Text(
                                l10n.lockWrongPin,
                                key: const ValueKey('lock-wrong'),
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              )
                            : null,
                      ),
                    ),
                    _Keypad(
                      bangla: bangla,
                      enabled: !lockedOut,
                      onDigit: _press,
                      onBackspace: _backspace,
                      onSubmit: _submit,
                      showBiometric: state.biometric,
                      onBiometric: _biometric,
                      biometricLabel: l10n.lockUseBiometric,
                      backspaceLabel: l10n.actionDelete,
                      submitLabel: l10n.actionOk,
                    ),
                    TextButton(
                      key: const ValueKey('lock-forgot'),
                      onPressed: () => setState(() {
                        _resetting = true;
                        _resetError = null;
                      }),
                      child: Text(l10n.lockForgot),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _resetPanel(AppL10n l10n) => [
    const SizedBox(height: 16),
    Text(l10n.lockResetTitle, style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    Text(l10n.lockResetBody, textAlign: TextAlign.center),
    if (_resetError != null) ...[
      const SizedBox(height: 8),
      Text(
        _resetError!,
        key: const ValueKey('lock-reset-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
        textAlign: TextAlign.center,
      ),
    ],
    const SizedBox(height: 16),
    FilledButton(
      key: const ValueKey('lock-reset-continue'),
      onPressed: _reset,
      child: Text(l10n.actionConfirm),
    ),
    TextButton(
      key: const ValueKey('lock-reset-cancel'),
      onPressed: () => setState(() => _resetting = false),
      child: Text(l10n.actionCancel),
    ),
  ];
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.error});

  final int count;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$count',
      child: SizedBox(
        height: 20,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: error ? scheme.error : scheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.bangla,
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
    required this.showBiometric,
    required this.onBiometric,
    required this.biometricLabel,
    required this.backspaceLabel,
    required this.submitLabel,
  });

  final bool bangla;
  final bool enabled;
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final bool showBiometric;
  final VoidCallback onBiometric;
  final String biometricLabel;
  final String backspaceLabel;
  final String submitLabel;

  Widget _key(Widget child, VoidCallback? onTap, {Key? key, String? label}) =>
      Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 88,
          height: 64,
          child: Semantics(
            label: label,
            button: true,
            excludeSemantics: label != null,
            child: FilledButton.tonal(
              key: key,
              onPressed: enabled ? onTap : null,
              child: child,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _key(
      Text(
        bangla ? DigitFormatter.toBangla(d) : d,
        style: const TextStyle(fontSize: 24),
      ),
      () => onDigit(d),
      key: ValueKey('pin-key-$d'),
    );
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) digit(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _key(
              const Icon(Icons.backspace_outlined),
              onBackspace,
              key: const ValueKey('pin-key-backspace'),
              label: backspaceLabel,
            ),
            digit('0'),
            _key(
              const Icon(Icons.check),
              onSubmit,
              key: const ValueKey('pin-key-submit'),
              label: submitLabel,
            ),
          ],
        ),
        if (showBiometric)
          TextButton.icon(
            key: const ValueKey('pin-key-biometric'),
            onPressed: enabled ? onBiometric : null,
            icon: const Icon(Icons.fingerprint),
            label: Text(biometricLabel),
          ),
      ],
    );
  }
}

/// Puts [LockScreen] over [child] while the app is locked, and locks the app
/// when it has been in the background too long.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockControllerProvider.notifier);
    switch (state) {
      // `inactive` already counts, so "lock immediately" also covers the
      // recent-apps preview, which is taken before the app is paused.
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.didLeave();
      case AppLifecycleState.resumed:
        lock.didReturn();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(lockControllerProvider.select((s) => s.locked));
    return Stack(
      fit: StackFit.expand,
      children: [
        // While locked the app stays alive underneath (no lost state) but
        // cannot be touched or read by a screen reader.
        ExcludeSemantics(
          excluding: locked,
          child: IgnorePointer(ignoring: locked, child: widget.child),
        ),
        if (locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}
