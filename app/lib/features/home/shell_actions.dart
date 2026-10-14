import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/sync/sync_service.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../calendar/calendars_screen.dart';
import '../settings/settings_screen.dart';

/// Sync state pill + overflow menu shown in every page header.
class ShellActions extends ConsumerWidget {
  const ShellActions({super.key, this.compact = false});

  /// Icon-only sync state, for headers that already carry controls.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final t = context.tokens;
    final SyncStatus status = ref.watch(syncStatusProvider).value ?? ref.read(syncServiceProvider).currentStatus;
    final (icon, label, color) = switch (status.phase) {
      SyncPhase.syncing => (Icons.sync_rounded, l.syncStatusSyncing, t.accent),
      SyncPhase.offline => (Icons.cloud_off_rounded, l.syncStatusOffline, t.secondary),
      SyncPhase.error || SyncPhase.unauthenticated => (Icons.sync_problem_rounded, l.syncStatusError, t.danger),
      SyncPhase.idle => status.pending > 0
          ? (Icons.cloud_upload_outlined, l.syncStatusPending(status.pending), t.accent)
          : (Icons.cloud_done_outlined, l.syncOk, t.secondary),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        message: [label, if (status.error != null) status.error!, l.syncNow].join(' · '),
        child: compact
            ? IconButton(
                icon: Badge(
                  isLabelVisible: status.pending > 0,
                  label: Text('${status.pending}'),
                  backgroundColor: t.accent,
                  child: Icon(icon, size: 20, color: color),
                ),
                onPressed: () => ref.read(syncServiceProvider).sync(),
              )
            : Pill(
          neutral: color == t.secondary,
          color: color == t.secondary ? null : color,
          icon: icon,
          // keep the pill short so it never squeezes the page title
          label: switch (status.phase) {
            SyncPhase.idle when status.pending > 0 => '${status.pending}',
            SyncPhase.idle => l.syncOk,
            SyncPhase.syncing => l.syncOk,
            _ => label,
          },
          onTap: () => ref.read(syncServiceProvider).sync(),
        ),
      ),
      PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz_rounded, color: t.secondary),
        onSelected: (v) {
          switch (v) {
            case 'calendars':
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CalendarsScreen()));
            case 'settings':
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
            case 'logout':
              ref.read(sessionProvider.notifier).logout();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'calendars', child: Text(l.calendars)),
          PopupMenuItem(value: 'settings', child: Text(l.settings)),
          PopupMenuItem(value: 'logout', child: Text(l.logout)),
        ],
      ),
    ]);
  }
}
