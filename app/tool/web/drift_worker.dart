// Entry point of the drift web worker, compiled to web/drift_worker.js by
// tool/fetch_web_assets.sh so it always matches the app's drift/sqlite3 versions.
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
