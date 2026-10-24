import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/features/customers/data/deleted_customers.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Customers that were removed, with a way back (B-8).
class RecentlyDeletedScreen extends ConsumerWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final deleted = ref.watch(deletedCustomersProvider);
    final now = ref.watch(clockProvider).now();
    final bangla = ref.watch(useBanglaDigitsProvider);

    String digits(String text) => bangla ? DigitFormatter.toBangla(text) : text;

    Future<void> restore(DeletedCustomer customer) async {
      await ref
          .read(deletedCustomerRepositoryProvider)
          .restore(customer.id, ref.read(clockProvider).now());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.deletedRestored(customer.name))),
        );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.deletedTitle)),
      body: deleted.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => EmptyState(
          icon: Icons.error_outline,
          title: l10n.backupErrFailed,
          body: '',
        ),
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.delete_sweep_outlined,
                title: l10n.deletedEmpty,
                body: l10n.deletedEmptyBody,
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final c = items[i];
                  return ListTile(
                    key: ValueKey('deleted-${c.id}'),
                    title: Text(c.name),
                    subtitle: Text(
                      c.hasHistory
                          ? l10n.deletedKeptHistory
                          : digits(l10n.deletedDaysLeft(c.daysLeft(now))),
                    ),
                    trailing: TextButton(
                      key: ValueKey('restore-${c.id}'),
                      onPressed: () => restore(c),
                      child: Text(l10n.deletedRestore),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
