import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../data/repositories/ics_service.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

const _palette = ['#3B82F6', '#EF4444', '#10B981', '#F59E0B', '#8B5CF6', '#EC4899', '#14B8A6', '#6B7280'];

/// Manage calendars: visibility, create/edit/delete, ICS subscriptions.
class CalendarsScreen extends ConsumerWidget {
  const CalendarsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final calendars = ref.watch(calendarsProvider).value ?? const <Calendar>[];
    final repo = ref.read(calendarRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.calendars)),
      body: ListView(
        children: [
          for (final c in calendars)
            ListTile(
              leading: Checkbox(
                value: c.visible,
                activeColor: colorFromHex(c.color),
                onChanged: (v) => repo.setVisible(c.id, v ?? true),
              ),
              title: Text(c.name),
              subtitle: Text([
                if (c.isDefault) l.defaultCalendar,
                if (c.source == 'ics') l.subscription,
              ].join(' · ')),
              trailing: c.source == 'ics'
                  ? IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: l.refresh,
                      onPressed: () => _refresh(context, ref, c),
                    )
                  : null,
              onTap: () => _editCalendar(context, ref, c),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l.newCalendar),
            onTap: () => _editCalendar(context, ref, null),
          ),
          ListTile(
            leading: const Icon(Icons.rss_feed),
            title: Text(l.subscribeIcs),
            subtitle: Text(l.icsHintHolidays),
            onTap: () => _subscribe(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref, Calendar c) async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref.read(icsServiceProvider).refresh(c);
      messenger.showSnackBar(SnackBar(content: Text(l.icsFetched(n))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.icsFetchFailed(e.toString()))));
    }
  }

  Future<void> _editCalendar(BuildContext context, WidgetRef ref, Calendar? c) async {
    final l = L10n.of(context);
    final name = TextEditingController(text: c?.name ?? '');
    var color = c?.color ?? _palette.first;
    var isDefault = c?.isDefault ?? false;
    final repo = ref.read(calendarRepositoryProvider);
    final all = ref.read(calendarsProvider).value ?? const <Calendar>[];
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(c == null ? l.newCalendar : l.editCalendar),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: l.name)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in _palette)
                    GestureDetector(
                      onTap: () => setState(() => color = p),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: colorFromHex(p),
                        child: color == p ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                      ),
                    ),
                ],
              ),
              if (c?.source != 'ics')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.makeDefault),
                  value: isDefault,
                  onChanged: (c?.isDefault ?? false) ? null : (v) => setState(() => isDefault = v ?? false),
                ),
            ],
          ),
          actions: [
            if (c != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: Text(l.delete, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(l.save)),
          ],
        ),
      ),
    );
    if (!context.mounted || result == null) return;
    if (result == 'delete') {
      if (c!.source == 'local' && all.where((x) => x.source == 'local').length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.cannotDeleteLast)));
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.deleteCalendarConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.delete)),
          ],
        ),
      );
      if (ok == true) await repo.remove(c.id);
      return;
    }
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.nameRequired)));
      return;
    }
    if (c == null) {
      await repo.create(name: name.text, color: color, isDefault: isDefault);
    } else {
      await repo.save(c.copyWith(name: name.text, color: color, isDefault: isDefault || c.isDefault));
    }
  }

  Future<void> _subscribe(BuildContext context, WidgetRef ref) async {
    final l = L10n.of(context);
    final name = TextEditingController(text: 'Resmî tatiller');
    final url = TextEditingController(text: IcsService.turkishHolidaysUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.subscribeIcs),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: l.name)),
            const SizedBox(height: 8),
            TextField(controller: url, decoration: InputDecoration(labelText: l.icsUrl), keyboardType: TextInputType.url, maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
        ],
      ),
    );
    if (ok != true || !context.mounted || url.text.trim().isEmpty) return;
    final sub = await ref.read(calendarRepositoryProvider).subscribe(name: name.text, url: url.text, color: '#EF4444');
    if (context.mounted) await _refresh(context, ref, sub);
  }
}
