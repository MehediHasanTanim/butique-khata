import 'package:flutter/material.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Placeholder tab bodies replaced feature by feature in later sprints.
class RushScreen extends StatelessWidget {
  const RushScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.rushTitle)),
      body: EmptyState(
        icon: Icons.local_fire_department_outlined,
        title: l10n.rushEmptyTitle,
        body: l10n.rushEmptyBody,
      ),
    );
  }
}
