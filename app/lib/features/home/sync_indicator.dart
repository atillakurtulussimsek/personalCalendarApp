import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_service.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// AppBar action: icon + tooltip reflecting the sync state; tap to sync now.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final SyncStatus status = ref.watch(syncStatusProvider).value ?? ref.read(syncServiceProvider).currentStatus;
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status.phase) {
      SyncPhase.syncing => (Icons.sync, l.syncStatusSyncing, scheme.primary),
      SyncPhase.offline => (Icons.cloud_off, l.syncStatusOffline, scheme.outline),
      SyncPhase.error || SyncPhase.unauthenticated => (Icons.sync_problem, l.syncStatusError, scheme.error),
      SyncPhase.idle => status.pending > 0
          ? (Icons.cloud_upload_outlined, l.syncStatusPending(status.pending), scheme.tertiary)
          : (Icons.cloud_done_outlined, l.syncStatusSynced, scheme.outline),
    };
    return IconButton(
      tooltip: '$label · ${l.syncNow}',
      icon: Badge(
        isLabelVisible: status.pending > 0 && status.phase != SyncPhase.syncing,
        label: Text('${status.pending}'),
        child: Icon(icon, color: color),
      ),
      onPressed: () => ref.read(syncServiceProvider).sync(),
    );
  }
}
