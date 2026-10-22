import 'package:flutter/material.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';

/// List row with a guaranteed 48 dp+ target and room for two lines.
class AppListTile extends StatelessWidget {
  const AppListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinTouchTarget),
      child: ListTile(
        leading: leading,
        trailing: trailing,
        onTap: onTap,
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
