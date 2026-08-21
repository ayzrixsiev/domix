import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One GET, retried **once** when the connection died rather than the server answering.
///
/// ## The bug this exists for
///
/// A phone that has been sitting idle keeps its last HTTP connection in Dart's pool, alive as far
/// as it knows. Nothing on the phone is told when the far end goes away, and three things routinely
/// take it away without a word: ngrok drops idle tunnel connections, carrier NAT forgets an idle TCP
/// flow, and the radio itself renegotiates when the handset wakes. The next request is written into
/// that dead socket, the socket closes, and Dart reports
/// `Connection closed before full header was received` - the request never reached Go, which is why
/// nothing is in the server's log and why the *second* attempt (a fresh connection) always works.
///
/// Reported as: opening one product from Изоляция failed once, on a phone that had been left alone,
/// and every retry by hand afterwards succeeded.
///
/// ## Why only a GET, and why only once
///
/// **A GET is the only method safe to repeat blindly** - it changes nothing, so a retry cannot
/// create a second shop or send a support message twice. A POST or a PUT that dies this way may
/// well have been received, and this helper must never be pointed at one.
///
/// **Once**, because this failure mode is a single stale connection: attempt two opens a new one and
/// either works or is a real outage, and a third attempt would only make an outage take three times
/// as long to say so. There is no backoff for the same reason - there is nothing to wait for.
///
/// A [TimeoutException] is deliberately **not** retried. It means the request did reach somewhere
/// and nothing came back in time, so a retry would double a ten-second wait into twenty and the
/// screen would read as hung rather than failed.
Future<http.Response> apiGet(
  Uri uri, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    return await http.get(uri, headers: headers).timeout(timeout);
  } on http.ClientException catch (e) {
    // the log is where the real sentence goes and the only place it is allowed to go: every screen
    // above this renders a written message, never an exception (see AppLocalizations).
    debugPrint('apiGet: connection failed once on $uri ($e) - retrying on a fresh connection');
  } on SocketException catch (e) {
    // package:http's IOClient turns these into ClientException, so reaching here means something
    // threw one straight past it. cheap to cover, and it is the same fault.
    debugPrint('apiGet: socket failed once on $uri ($e) - retrying on a fresh connection');
  } on HttpException catch (e) {
    debugPrint('apiGet: http framing failed once on $uri ($e) - retrying on a fresh connection');
  }

  return http.get(uri, headers: headers).timeout(timeout);
}
