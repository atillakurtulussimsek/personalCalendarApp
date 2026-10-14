import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Native (Android/macOS): SQLite file shared across isolates (WorkManager, FCM).
QueryExecutor openConnection(String name) => driftDatabase(
      name: name,
      native: const DriftNativeOptions(shareAcrossIsolates: true),
    );
