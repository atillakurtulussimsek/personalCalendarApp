import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/recurrence.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';

/// Hour-by-hour grid for 1 (day view) or 7 (week view) days with an all-day
/// row on top. Supports drag-to-move (across days too) and drag-to-resize via
/// the bottom handle of a block. Times snap to 15 minutes.
class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.firstDay,
    required this.days,
    required this.occurrences,
    required this.calendars,
    required this.onOpen,
    required this.onCreate,
    required this.onMove,
    required this.onResize,
    this.hourHeight = 56,
  });

  final DateTime firstDay; // local midnight
  final int days;
  final List<Occurrence> occurrences;
  final Map<String, Calendar> calendars;
  final void Function(Occurrence) onOpen;
  final void Function(DateTime start, bool allDay) onCreate;
  final Future<void> Function(Occurrence, Duration delta) onMove;
  final Future<void> Function(Occurrence, Duration newDuration) onResize;
  final double hourHeight;

  @override
  State<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<TimeGrid> {
  static const gutter = 48.0;
  static const snap = Duration(minutes: 15);
  final _scroll = ScrollController();

  // live drag state: raw pointer offset since drag start, snapped on read
  Occurrence? _dragging;
  Offset _dragRaw = Offset.zero;
  Duration? _resizeDuration;
  bool _busy = false;

  int _dragMinutes(double colWidth) => (_dragRaw.dy / widget.hourHeight * 60 / snap.inMinutes).round() * snap.inMinutes;
  int _dragDays(double colWidth) => widget.days > 1 ? (_dragRaw.dx / colWidth).round() : 0;
  Duration _dragDelta(double colWidth) => Duration(minutes: _dragMinutes(colWidth), days: _dragDays(colWidth));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = DateTime.now().hour;
      if (_scroll.hasClients) _scroll.jumpTo(math.max(0, (h - 1) * widget.hourHeight));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  DateTime _dayAt(int i) => widget.firstDay.add(Duration(days: i));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final allDayItems = widget.occurrences.where((o) => o.allDay || o.end.difference(o.start) >= const Duration(days: 1)).toList();
    final timed = widget.occurrences.where((o) => !allDayItems.contains(o)).toList();
    final now = DateTime.now();

    return LayoutBuilder(builder: (context, constraints) {
      final colWidth = (constraints.maxWidth - gutter) / widget.days;
      return Column(
        children: [
          // header: day names
          Row(
            children: [
              const SizedBox(width: gutter),
              for (var i = 0; i < widget.days; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onCreate(_dayAt(i), true),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Column(
                        children: [
                          Text(['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'][Dates.weekdayIndex(_dayAt(i))],
                              style: context.text.bodySmall?.copyWith(color: Dates.sameDay(_dayAt(i), now) ? t.accent : null)),
                          Text('${_dayAt(i).day}',
                              style: context.text.titleLarge?.copyWith(
                                color: Dates.sameDay(_dayAt(i), now) ? t.accent : t.ink,
                                fontFeatures: tabularFigures,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // all-day row
          if (allDayItems.isNotEmpty)
            SizedBox(
              height: math.min(72, 22.0 * _allDayRows(allDayItems) + 6),
              child: Row(
                children: [
                  const SizedBox(width: gutter),
                  for (var i = 0; i < widget.days; i++)
                    Expanded(
                      child: Column(
                        children: [
                          for (final o in allDayItems.where((o) => _coversDay(o, _dayAt(i))).take(3))
                            _Chip(occurrence: o, calendar: widget.calendars[o.calendarId], onTap: () => widget.onOpen(o)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: widget.hourHeight * 24,
                child: Stack(
                  children: [
                    // hour lines + labels
                    for (var h = 0; h < 24; h++)
                      Positioned(
                        top: h * widget.hourHeight,
                        left: 0,
                        right: 0,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: gutter,
                              child: Transform.translate(
                                offset: const Offset(0, -7),
                                child: Text(h == 0 ? '' : h.toString().padLeft(2, '0'),
                                    textAlign: TextAlign.center,
                                    style: context.text.bodySmall?.copyWith(fontSize: 12, color: t.faint, fontFeatures: tabularFigures)),
                              ),
                            ),
                            Expanded(child: Divider(height: 1, color: t.line)),
                          ],
                        ),
                      ),
                    // day columns (tap to create)
                    for (var i = 0; i < widget.days; i++)
                      Positioned(
                        left: gutter + i * colWidth,
                        top: 0,
                        width: colWidth,
                        height: widget.hourHeight * 24,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (d) {
                            final minutes = (d.localPosition.dy / widget.hourHeight * 60 / 30).floor() * 30;
                            widget.onCreate(_dayAt(i).add(Duration(minutes: minutes)), false);
                          },
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Dates.sameDay(_dayAt(i), now) && widget.days > 1 ? t.accent5 : null,
                              border: i > 0 ? Border(left: BorderSide(color: t.line)) : null,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    // events
                    for (var i = 0; i < widget.days; i++)
                      ..._layoutDay(timed, _dayAt(i)).map((p) => _positioned(p, i, colWidth)),
                    // now line
                    if (_nowIndex(now) >= 0)
                      Positioned(
                        top: (now.hour + now.minute / 60) * widget.hourHeight - 1,
                        left: gutter + _nowIndex(now) * colWidth,
                        width: colWidth,
                        child: Container(height: 2, color: t.danger),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  int _nowIndex(DateTime now) {
    for (var i = 0; i < widget.days; i++) {
      if (Dates.sameDay(_dayAt(i), now)) return i;
    }
    return -1;
  }

  bool _coversDay(Occurrence o, DateTime day) {
    final s = o.start.toLocal();
    final e = o.end.toLocal();
    return s.isBefore(day.add(const Duration(days: 1))) && e.isAfter(day);
  }

  int _allDayRows(List<Occurrence> items) {
    var maxRows = 1;
    for (var i = 0; i < widget.days; i++) {
      maxRows = math.max(maxRows, items.where((o) => _coversDay(o, _dayAt(i))).length.clamp(1, 3));
    }
    return maxRows;
  }

  /// Column-packing layout for overlapping events of one day.
  List<_Placed> _layoutDay(List<Occurrence> items, DateTime day) {
    final dayStart = day;
    final dayEnd = day.add(const Duration(days: 1));
    final todays = items.where((o) => _coversDay(o, day)).toList()..sort((a, b) => a.start.compareTo(b.start));
    final placed = <_Placed>[];
    // greedy clustering
    final clusters = <List<Occurrence>>[];
    DateTime? clusterEnd;
    for (final o in todays) {
      final s = o.start.toLocal();
      if (clusters.isEmpty || clusterEnd == null || !s.isBefore(clusterEnd)) {
        clusters.add([o]);
        clusterEnd = o.end.toLocal();
      } else {
        clusters.last.add(o);
        if (o.end.toLocal().isAfter(clusterEnd)) clusterEnd = o.end.toLocal();
      }
    }
    for (final cluster in clusters) {
      final columns = <List<Occurrence>>[];
      final colOf = <Occurrence, int>{};
      for (final o in cluster) {
        var placedIn = -1;
        for (var c = 0; c < columns.length; c++) {
          if (!columns[c].last.end.toLocal().isAfter(o.start.toLocal())) {
            columns[c].add(o);
            placedIn = c;
            break;
          }
        }
        if (placedIn < 0) {
          columns.add([o]);
          placedIn = columns.length - 1;
        }
        colOf[o] = placedIn;
      }
      for (final o in cluster) {
        final s = o.start.toLocal().isBefore(dayStart) ? dayStart : o.start.toLocal();
        final e = o.end.toLocal().isAfter(dayEnd) ? dayEnd : o.end.toLocal();
        placed.add(_Placed(o, s.difference(dayStart), e.difference(dayStart), colOf[o]!, columns.length));
      }
    }
    return placed;
  }

  Widget _positioned(_Placed p, int dayIndex, double colWidth) {
    final isDragging = identical(_dragging, p.occurrence);
    var startOff = p.start;
    var endOff = p.end;
    var dayShift = 0;
    if (isDragging) {
      if (_resizeDuration != null) {
        endOff = startOff + _resizeDuration!;
      } else {
        startOff += Duration(minutes: _dragMinutes(colWidth));
        endOff = startOff + (p.end - p.start);
        dayShift = _dragDays(colWidth);
      }
    }
    final minHeight = widget.hourHeight / 4;
    final top = startOff.inMinutes / 60 * widget.hourHeight;
    final height = math.max(minHeight, (endOff - startOff).inMinutes / 60 * widget.hourHeight);
    final w = colWidth / p.columns;
    final cal = widget.calendars[p.occurrence.calendarId];
    final color = colorFromHex(cal?.color ?? '#4F5BD5');
    final readOnly = cal?.source == 'ics';
    final t = context.tokens;
    final now = DateTime.now();
    // only the event happening right now is solid; everything else is a soft tint
    final solid = p.occurrence.start.isBefore(now) && p.occurrence.end.isAfter(now);
    final fg = solid ? Colors.white : color;
    return Positioned(
      top: top,
      left: gutter + (dayIndex + dayShift) * colWidth + p.column * w + 1,
      width: w - 2,
      height: height,
      child: GestureDetector(
        onTap: () => widget.onOpen(p.occurrence),
        // touch: long-press then drag; mouse: plain drag
        onLongPressStart: readOnly ? null : (_) => setState(() => _dragging = p.occurrence),
        onLongPressMoveUpdate: readOnly ? null : (d) => setState(() => _dragRaw = d.offsetFromOrigin),
        onLongPressEnd: readOnly ? null : (_) => _commitMove(colWidth),
        onPanStart: readOnly ? null : (_) => setState(() => _dragging = p.occurrence),
        onPanUpdate: readOnly ? null : (d) => setState(() => _dragRaw += d.delta),
        onPanEnd: readOnly ? null : (_) => _commitMove(colWidth),
        child: Opacity(
          opacity: isDragging ? 0.7 : 1,
          child: Container(
            decoration: BoxDecoration(
              color: solid ? color : color.withValues(alpha: .14),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(Radii.sm)),
              border: isDragging
                  ? Border.all(color: t.ink, width: 1.5)
                  : Border(left: BorderSide(color: color, width: 3)),
              boxShadow: solid ? [BoxShadow(color: color.withValues(alpha: .32), blurRadius: 16, offset: const Offset(0, 6))] : null,
            ),
            padding: const EdgeInsets.fromLTRB(Space.sm - 2, Space.xs, Space.sm - 2, 0),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    // one line per 16 px; the time only when there is room for it
                    // narrow columns (phone week view) never wrap: words would break mid-letter
                    final lines = c.maxWidth < 96 ? math.min(2, (c.maxHeight / 16).floor()) : (c.maxHeight / 16).floor();
                    final style = TextStyle(fontFamily: 'Inter', color: fg, fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, fontFeatures: tabularFigures);
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.occurrence.title, maxLines: lines > 2 ? lines - 1 : 1, overflow: TextOverflow.ellipsis, softWrap: lines > 2, style: style),
                      if (lines >= 2)
                        Text(Dates.time.format(p.occurrence.start.toLocal()),
                            maxLines: 1, overflow: TextOverflow.clip, style: style.copyWith(fontWeight: FontWeight.w400)),
                    ]);
                  }),
                ),
                if (!readOnly)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => setState(() {
                      _dragging = p.occurrence;
                      _resizeDuration = p.end - p.start;
                    }),
                    onVerticalDragUpdate: (d) => setState(() {
                      _dragRaw += Offset(0, d.delta.dy);
                      final dur = (p.end - p.start) + Duration(minutes: _dragMinutes(colWidth));
                      _resizeDuration = dur < snap ? snap : dur;
                    }),
                    onVerticalDragEnd: (_) => _commitResize(),
                    child: SizedBox(
                      height: 10,
                      width: double.infinity,
                      child: Center(child: Icon(Icons.drag_handle_rounded, size: 12, color: fg.withValues(alpha: .6))),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _commitMove(double colWidth) async {
    final o = _dragging;
    final delta = _dragDelta(colWidth);
    setState(() {
      _dragging = null;
      _dragRaw = Offset.zero;
    });
    if (o == null || delta == Duration.zero || _busy) return;
    _busy = true;
    try {
      await widget.onMove(o, delta);
    } finally {
      _busy = false;
    }
  }

  Future<void> _commitResize() async {
    final o = _dragging;
    final dur = _resizeDuration;
    setState(() {
      _dragging = null;
      _resizeDuration = null;
      _dragRaw = Offset.zero;
    });
    if (o == null || dur == null || dur == o.end.difference(o.start) || _busy) return;
    _busy = true;
    try {
      await widget.onResize(o, dur);
    } finally {
      _busy = false;
    }
  }
}

class _Placed {
  _Placed(this.occurrence, this.start, this.end, this.column, this.columns);
  final Occurrence occurrence;
  final Duration start;
  final Duration end;
  final int column;
  final int columns;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.occurrence, this.calendar, required this.onTap});
  final Occurrence occurrence;
  final Calendar? calendar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(1, 1, 1, 1),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: colorFromHex(calendar?.color ?? '#4F5BD5').withValues(alpha: .14),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Text(occurrence.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Inter', color: colorFromHex(calendar?.color ?? '#4F5BD5'), fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
