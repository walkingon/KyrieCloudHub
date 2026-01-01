import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../models/platform_credential.dart';
import '../../../utils/logger.dart';

/// 阿里云OSS V4签名生成器
///
/// 阿里云OSS V4签名算法说明：
/// 1. 使用 ISO8601 格式的日期时间 (如: 20250417T111832Z)
/// 2. Credential = AccessKeyId/YYYYMMDD/region/oss/aliyun_v4_request
/// 3. AdditionalHeaders = 参与签名的HTTP头部列表（按小写字母排序，分号分隔）
/// 4. 使用 HMAC-SHA256 计算签名
class AliyunSignatureGenerator {
  final PlatformCredential credential;
  final String region;
  final bool debugMode;

  AliyunSignatureGenerator({
    required this.credential,
    required this.region,
    this.debugMode = false,
  });

  /// 打印签名调试日志（仅在debugMode为true时打印）
  void _debugLog(String message) {
    if (debugMode) {
      log(message);
    }
  }

  /// 生成阿里云OSS V4签名
  String generate({
    required String method,
    String? bucketName,
    String? objectKey,
    required Map<String, String> headers,
    Map<String, String>? queryParams,
  }) {
    // 1. 生成 ISO8601 格式的日期时间
    final now = DateTime.now().toUtc();
    final dateTimeStr = _formatIso8601DateTime(now);
    final dateStr = dateTimeStr.substring(0, 8); // YYYYMMDD

    final normalizedRegion = _normalizeRegion(region);
    _debugLog('[AliyunOSS] 签名参数: dateStr=$dateStr, region=$normalizedRegion');

    // 2. 构建参与签名的头部列表（按小写字母排序）
    final signingHeaders = <String>[];
    for (final entry in headers.entries) {
      final lowerKey = entry.key.toLowerCase();
      // 参与签名的头部: host, content-type, content-md5, 以及 x-oss- 开头的头部
      if (lowerKey == 'host' ||
          lowerKey == 'content-type' ||
          lowerKey == 'content-md5' ||
          lowerKey.startsWith('x-oss-')) {
        signingHeaders.add(lowerKey);
      }
    }
    signingHeaders.sort();
    final signedHeadersStr = signingHeaders.join(';');
    _debugLog('[AliyunOSS] SignedHeaders: $signedHeadersStr');

    // 3. 构建 CanonicalHeader
    final canonicalHeaders = <String>[];
    for (final key in signingHeaders) {
      final value = headers.entries
          .firstWhere((e) => e.key.toLowerCase() == key, orElse: () => MapEntry('', ''))
          .value;
      canonicalHeaders.add('$key:${value.trim()}');
    }
    final canonicalHeadersStr = canonicalHeaders.join('\n');
    _debugLog('[AliyunOSS] CanonicalHeaders: """$canonicalHeadersStr"""');

    // 4. 构建 Canonical URI
    String canonicalUri = '/';
    if (bucketName != null) {
      if (objectKey != null && objectKey.isNotEmpty) {
        canonicalUri = '/$bucketName/${_encodePath(objectKey)}';
      } else {
        canonicalUri = '/$bucketName/';
      }
    }
    _debugLog('[AliyunOSS] CanonicalUri: $canonicalUri');

    // 5. 构建 Canonical Query String
    String canonicalQueryString = '';
    if (queryParams != null && queryParams.isNotEmpty) {
      final sortedParams = queryParams.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      canonicalQueryString = sortedParams
          .map((e) {
            final encodedKey = Uri.encodeComponent(e.key);
            if (e.value.isEmpty) {
              return encodedKey;
            }
            if (e.key == 'marker') {
              if (e.value.contains('%')) {
                return '$encodedKey=${e.value}';
              }
              return '$encodedKey=${_encodeMarkerValue(e.value)}';
            }
            return '$encodedKey=${Uri.encodeComponent(e.value)}';
          })
          .join('&');
    }
    _debugLog('[AliyunOSS] CanonicalQueryString: """$canonicalQueryString"""');

    // 6. 构建 CanonicalRequest
    final canonicalRequest = [
      method.toUpperCase(),
      canonicalUri,
      canonicalQueryString,
      '$canonicalHeadersStr\n',
      signedHeadersStr,
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    _debugLog('[AliyunOSS] CanonicalRequest: """$canonicalRequest"""');

    // 7. 构建 StringToSign
    final canonicalRequestHash = _sha256Hex(canonicalRequest);
    _debugLog('[AliyunOSS] CanonicalRequestHash: $canonicalRequestHash');

    final stringToSign = [
      'OSS4-HMAC-SHA256',
      dateTimeStr,
      '$dateStr/$normalizedRegion/oss/aliyun_v4_request',
      canonicalRequestHash,
    ].join('\n');

    _debugLog('[AliyunOSS] StringToSign: """$stringToSign"""');

    // 8. 计算签名密钥链
    final dateKeyInput = 'aliyun_v4${credential.secretKey}';
    _debugLog('[AliyunOSS] DateKeyInput: $dateKeyInput (长度: ${dateKeyInput.length})');

    final kDateBytes = _hmacSha256Bytes(dateKeyInput, dateStr);
    _debugLog('[AliyunOSS] KDate (hex): ${_bytesToHex(kDateBytes)}');

    final kRegionBytes = _hmacSha256WithBytesKey(kDateBytes, normalizedRegion);
    _debugLog('[AliyunOSS] KRegion (hex): ${_bytesToHex(kRegionBytes)}');

    final kServiceBytes = _hmacSha256WithBytesKey(kRegionBytes, 'oss');
    _debugLog('[AliyunOSS] KService (hex): ${_bytesToHex(kServiceBytes)}');

    final kSigningBytes = _hmacSha256WithBytesKey(kServiceBytes, 'aliyun_v4_request');
    _debugLog('[AliyunOSS] KSigning (hex): ${_bytesToHex(kSigningBytes)}');

    // 9. 计算签名
    final signature = _hmacSha256WithBytesKeyHex(kSigningBytes, stringToSign);
    _debugLog('[AliyunOSS] Signature: $signature');

    // 10. 构建 Credential 和 Authorization
    final credentialStr = '${credential.secretId}/$dateStr/$normalizedRegion/oss/aliyun_v4_request';
    _debugLog('[AliyunOSS] Credential: $credentialStr');

    final authorization =
        'OSS4-HMAC-SHA256 Credential=$credentialStr,AdditionalHeaders=$signedHeadersStr,Signature=$signature';
    _debugLog('[AliyunOSS] Authorization: $authorization');

    return authorization;
  }

  /// 格式化 ISO8601 日期时间
  String _formatIso8601DateTime(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}'
        'T'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}'
        'Z';
  }

  /// 规范化地域格式
  String _normalizeRegion(String region) {
    if (region.startsWith('oss-')) {
      return region.substring(4);
    }
    final mapping = {
      'ap-beijing': 'cn-beijing',
      'ap-nanjing': 'cn-nanjing',
      'ap-shanghai': 'cn-shanghai',
      'ap-hangzhou': 'cn-hangzhou',
      'ap-guangzhou': 'cn-guangzhou',
      'ap-shenzhen': 'cn-shenzhen',
      'cn-beijing': 'cn-beijing',
      'cn-shanghai': 'cn-shanghai',
      'cn-hangzhou': 'cn-hangzhou',
      'cn-shenzhen': 'cn-shenzhen',
      'cn-guangzhou': 'cn-guangzhou',
      'cn-hongkong': 'cn-hongkong',
    };
    return mapping[region] ?? region;
  }

  /// 对路径进行 URI 编码（不编码正斜杠）
  String _encodePath(String path) {
    return Uri.encodeComponent(path)
        .replaceAll('%2F', '/')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29');
  }

  /// marker 值的特殊编码
  String _encodeMarkerValue(String value) {
    String encoded = Uri.encodeComponent(value);
    encoded = encoded.replaceAll('(', '%28').replaceAll(')', '%29');
    return encoded;
  }

  /// HMAC-SHA256 计算，返回十六进制字符串
  String _hmacSha256WithBytesKeyHex(List<int> keyBytes, String data) {
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(dataBytes);
    return digest.toString();
  }

  /// HMAC-SHA256 计算，返回字节
  List<int> _hmacSha256Bytes(String key, String data) {
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(dataBytes);
    return digest.bytes;
  }

  /// HMAC-SHA256 计算，使用字节作为key，返回字节
  List<int> _hmacSha256WithBytesKey(List<int> keyBytes, String data) {
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(dataBytes);
    return digest.bytes;
  }

  /// SHA256 计算，返回十六进制字符串
  String _sha256Hex(String data) {
    final dataBytes = utf8.encode(data);
    final hash = sha256.convert(dataBytes);
    return hash.toString();
  }

  /// 字节数组转十六进制字符串
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
}
