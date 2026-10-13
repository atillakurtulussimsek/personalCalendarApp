import 'package:flutter/material.dart';

import '../../data/repositories/repositories.dart';
import '../../l10n/app_localizations.dart';

/// "Only this / this and following / all" chooser for recurring events.
Future<EditScope?> showEditScopeDialog(BuildContext context, {bool allowFollowing = true}) {
  final l = L10n.of(context);
  return showDialog<EditScope>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l.editScopeTitle),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx, EditScope.onlyThis), child: Text(l.editScopeOnlyThis)),
        if (allowFollowing)
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, EditScope.thisAndFollowing), child: Text(l.editScopeFollowing)),
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx, EditScope.all), child: Text(l.editScopeAll)),
      ],
    ),
  );
}
