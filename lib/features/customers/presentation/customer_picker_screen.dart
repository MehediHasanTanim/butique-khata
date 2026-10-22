import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Pick a customer for a new order. Pops with the customer id; "New
/// customer" creates one first.
class CustomerPickerScreen extends ConsumerStatefulWidget {
  const CustomerPickerScreen({super.key});

  @override
  ConsumerState<CustomerPickerScreen> createState() =>
      _CustomerPickerScreenState();
}

class _CustomerPickerScreenState extends ConsumerState<CustomerPickerScreen> {
  final _controller = TextEditingController();
  Timer? _timer;
  Stream<List<Customer>>? _stream;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _stream = ref.read(customerRepositoryProvider).watchSearch(value);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    _stream ??= ref.read(customerRepositoryProvider).watchSearch('');
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pickCustomer)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.customerNew),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(l10n.customerAdd),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: l10n.customerSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Customer>>(
              stream: _stream,
              builder: (context, snapshot) {
                final list = snapshot.data ?? const <Customer>[];
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final c = list[i];
                    final phone = c.phoneDisplay;
                    return ListTile(
                      key: ValueKey('pick-${c.id}'),
                      minTileHeight: 56,
                      leading: CircleAvatar(child: Text(c.initial)),
                      title: Text(c.name),
                      subtitle: phone == null
                          ? null
                          : Text(DigitFormatter.format(phone, bangla: bangla)),
                      onTap: () => context.pop(c.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
