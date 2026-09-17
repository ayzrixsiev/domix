import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// The one HTTP client every request goes through. package:http's `http.get()` builds a fresh client
/// per call, so every request paid for a new TCP + TLS handshake (~0.3 s on mobile); shared, the
/// connection stays open.
///
/// idleTimeout sits below the server's keep-alive (nginx 75 s, Go 120 s), so the phone closes a quiet
/// connection first - the other way round is what leaves a dead socket. [apiGet] retries once for it.
final http.Client appHttpClient = IOClient(
  HttpClient()
    ..idleTimeout = const Duration(seconds: 15)
    ..connectionTimeout = const Duration(seconds: 10),
);

/// One GET, retried once when the connection died rather than the server answering. **GET only** - a
/// blind retry must never create a second shop - and never after a timeout, which means it did arrive.
Future<http.Response> apiGet(
  Uri uri, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    return await appHttpClient.get(uri, headers: headers).timeout(timeout);
  } on http.ClientException catch (e) {
    // the log is the only place the real sentence is allowed to go: every screen above renders
    // written copy, never an exception
    debugPrint('apiGet: connection failed once on $uri ($e) - retrying');
  } on SocketException catch (e) {
    // IOClient normally wraps these in ClientException; cheap to cover, same fault
    debugPrint('apiGet: socket failed once on $uri ($e) - retrying');
  } on HttpException catch (e) {
    debugPrint('apiGet: http framing failed once on $uri ($e) - retrying');
  }

  return appHttpClient.get(uri, headers: headers).timeout(timeout);
}

/// A request the server refused. Only the status is kept; the sentence comes from [LoadFailure].
class ApiException implements Exception {
  const ApiException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'ApiException($statusCode)';
}

/// Why a read failed, in the terms a screen needs. "Проверьте подключение" is only true of [network].
enum LoadFailure {
  /// no answer at all: no connection, a dropped one, or a timeout
  network,

  /// 429 or 503 - come back in a minute
  busy,

  /// the server answered with an error, or with something this build could not read
  server;

  static LoadFailure of(Object error) => switch (error) {
        ApiException(statusCode: 429 || 503) => busy,
        ApiException() => server,
        TimeoutException() ||
        SocketException() ||
        HttpException() ||
        TlsException() ||
        http.ClientException() =>
          network,
        _ => server,
      };
}
