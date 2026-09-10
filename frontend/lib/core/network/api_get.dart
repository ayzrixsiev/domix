import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One GET, retried **once** when the connection died rather than the server answering: an idle
/// phone keeps a dead socket in Dart's pool, and the request fails with `Connection closed before
/// full header was received` without ever reaching Go, so a fresh connection always works.
///
/// **GET only** - a blind retry must never create a second shop. A [TimeoutException] is not
/// retried: that request did arrive, so a second wait only makes the screen read as hung.
Future<http.Response> apiGet(
  Uri uri, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    return await http.get(uri, headers: headers).timeout(timeout);
  } on http.ClientException catch (e) {
    // the log is the only place the real sentence is allowed to go: every screen above renders
    // written copy, never an exception
    debugPrint('apiGet: connection failed once on $uri ($e) - retrying on a fresh connection');
  } on SocketException catch (e) {
    // package:http's IOClient normally wraps these in ClientException; cheap to cover, same fault
    debugPrint('apiGet: socket failed once on $uri ($e) - retrying on a fresh connection');
  } on HttpException catch (e) {
    debugPrint('apiGet: http framing failed once on $uri ($e) - retrying on a fresh connection');
  }

  return http.get(uri, headers: headers).timeout(timeout);
}
