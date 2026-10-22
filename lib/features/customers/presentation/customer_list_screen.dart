import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  static const _debounce = Duration(milliseconds: 250);

  final _controller = TextEditingController();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted) ref.read(customerSearchQueryProvider.notifier).set(value);
    });
    setState(() {});
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    ref.read(customerSearchQueryProvider.notifier).set('');
    setState(() {});
  }

  Future<void> _delete(Customer customer) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final delete = ref.read(deleteCustomerProvider);
    await delete(customer.id);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.customerDeleted(customer.name)),
          action: SnackBarAction(
            label: l10n.actionUndo,
            onPressed: () => delete.undo(customer.id),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final customers = ref.watch(customerListProvider);
    final query = ref.watch(customerSearchQueryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.customersTitle)),
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
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.customerSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
              ),
            ),
          ),
          Expanded(
            child: customers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(l10n.errorGenericTitle)),
              data: (list) {
                if (list.isEmpty) {
                  return query.trim().isEmpty
                      ? EmptyState(
                          icon: Icons.people_outline,
                          title: l10n.customersEmptyTitle,
                          body: l10n.customersEmptyBody,
                          action: PrimaryButton(
                            label: l10n.customerAdd,
                            icon: Icons.person_add_alt_1,
                            onPressed: () =>
                                context.push(AppRoutes.customerNew),
                          ),
                        )
                      : EmptyState(
                          icon: Icons.search_off,
                          title: l10n.noResults(query.trim()),
                          body: '',
                        );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  itemBuilder: (context, index) => _CustomerTile(
                    key: ValueKey(list[index].id),
                    customer: list[index],
                    onDelete: _delete,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends ConsumerWidget {
  const _CustomerTile({
    required this.customer,
    required this.onDelete,
    super.key,
  });

  final Customer customer;
  final Future<void> Function(Customer) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final phone = customer.phoneDisplay;
    return Dismissible(
      key: ValueKey('dismiss-${customer.id}'),
      background: Container(
        color: scheme.primaryContainer,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsetsDirectional.only(start: 24),
        child: Icon(Icons.edit, color: scheme.onPrimaryContainer),
      ),
      secondaryBackground: Container(
        color: scheme.errorContainer,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          unawaited(context.push(AppRoutes.customerEdit(customer.id)));
          return false;
        }
        return true;
      },
      onDismissed: (_) => onDelete(customer),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTouchTarget),
        child: ListTile(
          leading: CircleAvatar(child: Text(customer.initial)),
          title: Text(
            customer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: phone == null
              ? null
              : Text(DigitFormatter.format(phone, bangla: bangla)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.customer(customer.id)),
        ),
      ),
    );
  }
}
