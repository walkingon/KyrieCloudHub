import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../models/platform_credential.dart';
import '../../../utils/logger.dart';

/// 腾讯云COS签名生成器
///
/// 腾讯云COS签名算法说明：
/// 1. 使用 HMAC-SHA1 算法
/// 2. KeyTime = "startTimestamp;endTimestamp"
/// 3. SignKey = HMAC-SHA1(SecretKey, KeyTime)
/// 4. CanonicalRequest = SHA1(CanonicalRequest)
/// 5. StringToSign = "sha1\n{q-sign-time}\n{SHA1(CanonicalRequest)}\n"
/// 6. Signature = HMAC-SHA1(SignKey, StringToSign)
class TencentSignatureGenerator {
  final PlatformCredential credential;
  final bool debugMode;

  TencentSignatureGenerator({
    required this.credential,
    this.debugMode = false,
  });

  /// 打印签名调试日志
  void _debugLog(String message) {
    if (debugMode) {
      log(message);
    }
  }

  /// 生成腾讯云COS签名
  ///
  /// [method] HTTP方法
  /// [path] 请求路径（不含查询参数）
  /// [headers] 请求头
  /// [queryParams] 查询参数（可选）
  String generate({
    required String method,
    required String path,
    required Map<String, String> headers,
    Map<String, String>? queryParams,
  }) {
    // 生成签名时间（当前时间戳，有效期1小时）
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final end = now + 3600;
    final keyTime = '$now;$end';

    _debugLog('[TencentCOS] 签名 KeyTime: $keyTime');

    // 1. 计算 SignKey = HMAC-SHA1(SecretKey, KeyTime)
    final signKey = _hmacSha1(credential.secretKey, keyTime);
    _debugLog('[TencentCOS] 签名 SignKey: $signKey');

    // 2. 计算 CanonicalRequest 的 SHA1 哈希
    final canonicalRequest = _buildCanonicalRequest(method, path, headers, queryParams: queryParams);
    final sha1CanonicalRequest = sha1.convert(utf8.encode(canonicalRequest));
    _debugLog('[TencentCOS] 签名 CanonicalRequest SHA1: ${sha1CanonicalRequest.toString()}');

    // 3. 拼接 StringToSign
    final stringToSign = 'sha1\n$keyTime\n${sha1CanonicalRequest.toString()}\n';
    _debugLog('[TencentCOS] 签名 StringToSign: $stringToSign');

    // 4. 计算 Signature
    final signatureHex = _hmacSha1WithHexKey(signKey, stringToSign);
    _debugLog('[TencentCOS] 签名最终 Signature: $signatureHex');

    return signatureHex;
  }

  /// 构建规范请求 (CanonicalRequest)
  String _buildCanonicalRequest(
    String method,
    String path,
    Map<String, String> headers, {
    Map<String, String>? queryParams,
  }) {
    // 1. HttpMethod 转小写
    final httpMethod = method.toLowerCase();

    // 2. UriPathname
    final uriPathname = path;

    // 3. HttpParameters
    String httpParameters = '';
    if (queryParams != null && queryParams.isNotEmpty) {
      final sortedParams = queryParams.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

      httpParameters = sortedParams
          .map((e) {
            final key = Uri.encodeComponent(e.key.toLowerCase());
            final value = _encodeMarkerValue(e.value);
            return '$key=$value';
          })
          .join('&');
    }

    _debugLog('[TencentCOS] CanonicalRequest HttpParameters: $httpParameters');

    // 4. HttpHeaders (参与签名的头部)
    final sortedHeaders = headers.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    final httpHeaders = sortedHeaders
        .map((e) {
          final key = Uri.encodeComponent(e.key.toLowerCase());
          final value = Uri.encodeComponent(e.value);
          return '$key=$value';
        })
        .join('&');

    _debugLog('[TencentCOS] CanonicalRequest HttpHeaders: $httpHeaders');

    // 拼接
    final canonicalRequest = '$httpMethod\n$uriPathname\n$httpParameters\n$httpHeaders\n';
    _debugLog('[TencentCOS] CanonicalRequest完整: $canonicalRequest');

    return canonicalRequest;
  }

  /// marker 值的特殊编码
  String _encodeMarkerValue(String value) {
    String encoded = Uri.encodeComponent(value);
    encoded = encoded.replaceAll('(', '%28').replaceAll(')', '%29');
    return encoded;
  }

  /// HMAC-SHA1 计算，返回十六进制字符串
  String _hmacSha1(String key, String data) {
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha1, keyBytes);
    final digest = hmac.convert(dataBytes);
    return digest.toString();
  }

  /// HMAC-SHA1 计算，SignKey 为十六进制字符串
  String _hmacSha1WithHexKey(String hexKey, String data) {
    final keyBytes = utf8.encode(hexKey);
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha1, keyBytes);
    final digest = hmac.convert(dataBytes);
    return digest.toString();
  }
}
