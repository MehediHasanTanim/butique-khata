import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/domain/save_customer.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Create (no [customerId]) or edit a customer.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({this.customerId, super.key});

  final String? customerId;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();

  Customer? _existing;
  bool _loading = true;
  bool _saving = false;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.customerId;
    if (id != null) {
      final customer = await ref.read(customerRepositoryProvider).byId(id);
      if (customer != null) {
        _existing = customer;
        _name.text = customer.name;
        _phone.text = customer.phoneDisplay ?? '';
        _address.text = customer.address ?? '';
        _note.text = customer.note ?? '';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save({bool allowDuplicate = false}) async {
    final l10n = AppL10n.of(context);
    setState(() => _phoneError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final result = await ref.read(saveCustomerProvider)(
      CustomerInput(
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
        note: _note.text,
      ),
      existing: _existing,
      allowDuplicatePhone: allowDuplicate,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    final failure = result.failureOrNull;
    if (failure == null) {
      final customer = result.valueOrNull!;
      if (_existing == null) {
        // New customer: continue straight to their profile.
        context.pushReplacement(AppRoutes.customer(customer.id));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.customerSaved)));
        context.pop();
      }
      return;
    }
    switch (failure) {
      case DuplicatePhoneFailure(:final existing):
        await _askAboutDuplicate(existing);
      default:
        if (failure.code == 'customer.phone_invalid') {
          setState(() => _phoneError = l10n.phoneInvalid);
        }
    }
  }

  Future<void> _askAboutDuplicate(Customer existing) async {
    final l10n = AppL10n.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.duplicatePhoneTitle),
        content: Text(l10n.duplicatePhoneBody(existing.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'open'),
            child: Text(l10n.duplicateOpenExisting(existing.name)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(l10n.duplicateSaveAnyway),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'open') {
      context.pushReplacement(AppRoutes.customer(existing.id));
    } else if (choice == 'save') {
      await _save(allowDuplicate: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final editing = widget.customerId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? l10n.customerEdit : l10n.customerNew),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: !editing,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: l10n.fieldName),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? l10n.nameRequired : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.fieldPhone,
                      errorText: _phoneError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _address,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: l10n.fieldAddress),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _note,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: l10n.fieldNote),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: l10n.actionSave,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
    );
  }
}
