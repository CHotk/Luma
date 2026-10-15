// ignore_for_file: unnecessary_lambdas
// （append 是 JS 那邊的方法，不能直接當函式傳，一定要包一層。）

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// 網頁版：直接用瀏覽器 fetch，指定 `cache: 'no-store'`（不讀也不存 HTTP
/// 快取）。package:http 的 BrowserClient 沒辦法指定這個，所以自己包一個。
http.Client createR2HttpClient() => _NoStoreClient();

class _NoStoreClient extends http.BaseClient {
  /// 呼叫端（[R2Client]）會看的回應標頭。
  static const _keep = ['etag', 'content-type', 'content-length'];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final headers = web.Headers();
    request.headers.forEach((k, v) => headers.append(k, v));
    final web.Response res;
    final Uint8List bytes;
    try {
      res = await web.window
          .fetch(
            request.url.toString().toJS,
            web.RequestInit(
              method: request.method,
              headers: headers,
              body: body.isEmpty ? null : body.toJS,
              cache: 'no-store',
            ),
          )
          .toDart;
      bytes = (await res.arrayBuffer().toDart).toDart.asUint8List();
    } catch (e) {
      throw http.ClientException('$e', request.url);
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      res.status,
      contentLength: bytes.length,
      request: request,
      headers: {
        for (final k in _keep)
          if (res.headers.get(k) case final v?) k: v,
      },
    );
  }
}
