import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Serves [files] by URL path and counts requests; [offline] fails them all.
class FakeCdn implements HttpClientAdapter {
  final files = <String, List<int>>{};
  final requests = <String>[];
  bool offline = false;

  Dio get dio => Dio()..httpClientAdapter = this;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri.path);
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final body = files[options.uri.path];
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromBytes(
      body,
      200,
      headers: {
        Headers.contentLengthHeader: ['${body.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
