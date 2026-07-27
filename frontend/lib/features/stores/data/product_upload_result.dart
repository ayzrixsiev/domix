// what the backend returns from POST /api/products/upload (see backend/internal/endpoints/products.go) -
// counts only, no per-row detail: malformed rows are skipped silently server-side by design.
class ProductUploadResult {
  const ProductUploadResult({
    required this.rowsInFile,
    required this.processed,
    required this.skipped,
  });

  final int rowsInFile;
  final int processed;
  final int skipped;

  // a file whose rows were all unreadable is technically a success (nothing crashed) but is not
  // what the owner wanted, so the ui gives it its own warning treatment
  bool get isEmptyResult => processed == 0;

  factory ProductUploadResult.fromJson(Map<String, dynamic> json) {
    return ProductUploadResult(
      rowsInFile: json['rows_in_file'] as int? ?? 0,
      processed: json['processed'] as int? ?? 0,
      skipped: json['skipped'] as int? ?? 0,
    );
  }
}

// the backend's error strings are english, and this app only ever renders ru/uz - so failures carry
// a stable machine-readable `code` (see writeUploadError in backend/internal/endpoints/products.go)
// that the ui turns into a localized message. `message` is kept only for debug logging.
class ProductUploadException implements Exception {
  const ProductUploadException({required this.code, required this.message, this.limit});

  final String code;
  final String message;

  // only sent with code == "too_many_rows", so the message can name the real cap instead of
  // hardcoding 50 in the app and drifting the day the backend changes it
  final int? limit;

  @override
  String toString() => 'ProductUploadException($code): $message';
}
