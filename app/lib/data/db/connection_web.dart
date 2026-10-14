import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Web: SQLite compiled to WebAssembly (web/sqlite3.wasm + web/drift_worker.js).
///
/// drift picks the best storage the browser *claims* to support, but some
/// embedded browsers expose SharedWorker without letting it fetch (the wasm
/// download then fails). Every worker-based option is therefore verified on a
/// throwaway database first; if none works, the database runs in this tab on
/// IndexedDB (no cross-tab locking, still persistent).
QueryExecutor openConnection(String name) => DatabaseConnection.delayed(Future(() async {
      final sqlite3Uri = Uri.base.resolve('sqlite3.wasm');
      final workerUri = Uri.base.resolve('drift_worker.js');
      final probe = await WasmDatabase.probe(sqlite3Uri: sqlite3Uri, driftWorkerUri: workerUri, databaseName: name);
      final candidates = probe.availableStorages.toList()..sort((a, b) => a.index.compareTo(b.index));
      for (final impl in candidates) {
        if (impl == WasmStorageImplementation.unsafeIndexedDb || impl == WasmStorageImplementation.inMemory) break;
        try {
          final test = await probe.open(impl, '${name}_probe', enableMigrations: false);
          await test.executor.ensureOpen(_ProbeUser());
          await test.executor.runSelect('SELECT 1', const []);
          await test.executor.close();
          debugPrint('drift: using $impl');
          return await probe.open(impl, name);
        } catch (e) {
          debugPrint('drift: $impl unusable here ($e), trying next');
        }
      }
      debugPrint('drift: falling back to unsafeIndexedDb');
      return probe.open(WasmStorageImplementation.unsafeIndexedDb, name);
    }));

class _ProbeUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}
