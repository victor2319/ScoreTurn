import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'score.dart';
import 'score_document.dart';

class DocumentStore {
  static File fileFor(Score score) =>
      File('${File(score.localPaths.first).parent.path}/recognition.json');
  static Future<ScoreDocument?> load(Score score) async {
    final file = fileFor(score);
    if (!await file.exists()) return null;
    final document = ScoreDocument.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
    if (document.pages.length != score.pageCount)
      throw const FormatException('识谱页数与原谱不一致');
    return document;
  }

  static Future<void> save(Score score, ScoreDocument document) async {
    document.validate();
    if (document.pages.length != score.pageCount)
      throw const FormatException('识谱页数与原谱不一致');
    final file = fileFor(score), temp = File('${fileFor(score).path}.tmp');
    await temp.writeAsString(jsonEncode(document.toJson()), flush: true);
    await temp.rename(file.path);
  }
}

class RecognitionClient {
  HttpClient? _client;
  void cancel() {
    _client?.close(force: true);
    _client = null;
  }

  Future<ScoreDocument> recognize(
    Score score,
    String endpoint,
    String token,
  ) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const FormatException('请输入不含账号、查询参数的 HTTPS 识谱地址');
    }
    if (score.isPdf) throw const FormatException('此版本识谱入口支持照片；PDF 可继续使用原阅读器');
    final pages = <String>[];
    var total = 0;
    for (final path in score.localPaths) {
      final bytes = await File(path).readAsBytes();
      total += bytes.length;
      if (total > 40 * 1024 * 1024)
        throw const FormatException('识谱照片总量不能超过 40 MB');
      pages.add(base64Encode(bytes));
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _client = client;
    try {
      return await (() async {
        final request = await client.postUrl(uri);
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${token.trim()}',
        );
        request.add(utf8.encode(jsonEncode({'pages': pages})));
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 32 * 1024 * 1024)
            throw const FormatException('识谱响应过大');
          bytes.addAll(chunk);
        }
        final body = jsonDecode(utf8.decode(bytes));
        if (response.statusCode != 200)
          throw HttpException(
            '识谱服务 ${response.statusCode}：${body is Map ? body['error'] ?? '请求失败' : '请求失败'}',
          );
        final document = ScoreDocument.fromJson(
          Map<String, dynamic>.from(body),
        );
        if (document.pages.length != score.pageCount)
          throw const FormatException('部分页面未识别，请重新校对');
        document.reviewed = false;
        return document;
      })().timeout(const Duration(minutes: 11));
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }
}
