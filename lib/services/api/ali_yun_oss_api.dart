import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../../models/bucket.dart';
import '../../models/object_file.dart';
import '../../models/platform_credential.dart';
import '../../utils/logger.dart';
import 'cloud_platform_api.dart';
import 'http_client.dart';
import '../multipart_upload/file_chunk_reader.dart';

/// 阿里云OSS API实现
///
/// 阿里云OSS V4签名算法说明：
/// 1. 使用 ISO8601 格式的日期时间 (如: 20250417T111832Z)
/// 2. Credential = AccessKeyId/YYYYMMDD/region/oss/aliyun_v4_request
/// 3. AdditionalHeaders = 参与签名的HTTP头部列表（按小写字母排序，分号分隔）
/// 4. 使用 HMAC-SHA256 计算签名
class AliyunOssApi implements ICloudPlatformApi {
  final PlatformCredential credential;
  final HttpClient httpClient;

  AliyunOssApi(this.credential, this.httpClient);

  /// 生成阿里云OSS V4签名
  String _getSignatureV4({
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

    // 2. 确定地域
    final region = _getRegion();
    //log('[AliyunOSS] 签名参数: dateStr=$dateStr, region=$region');

    // 3. 构建参与签名的头部列表（按小写字母排序）
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
    //log('[AliyunOSS] SignedHeaders: $signedHeadersStr');

    // 4. 构建 CanonicalizedHeader
    // 注意：根据阿里云文档，每个header格式为 "key:value\n"，头部之间无额外换行
    final canonicalHeaders = <String>[];
    for (final key in signingHeaders) {
      final value = headers[key.toLowerCase()] ?? '';
      canonicalHeaders.add('$key:${value.trim()}');
    }
    // CanonicalHeaders: 每个header一行，header之间无空行
    final canonicalHeadersStr = canonicalHeaders.join('\n');
    //log('[AliyunOSS] CanonicalHeaders: """$canonicalHeadersStr"""');

    // 5. 构建 Canonical URI 和 Canonical Query String
    // 注意：Canonical URI 需要 URI 编码，但正斜杠 / 不需要编码
    String canonicalUri = '/';
    if (bucketName != null) {
      if (objectKey != null && objectKey.isNotEmpty) {
        // 有具体对象路径时: /bucketName/objectKey
        // 对 objectKey 进行 URI 编码，但不编码 /
        canonicalUri = '/$bucketName/${_encodePath(objectKey)}';
      } else {
        // 仅访问存储桶时（如列举对象）: /bucketName/ (需要末尾斜杠)
        canonicalUri = '/$bucketName/';
      }
    }
    //log('[AliyunOSS] CanonicalUri: $canonicalUri');

    // 构建 Canonical Query String（与阿里云官方SDK一致：空值不添加等号）
    String canonicalQueryString = '';
    if (queryParams != null && queryParams.isNotEmpty) {
      final sortedParams = queryParams.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      canonicalQueryString = sortedParams
          .map((e) {
            final encodedKey = Uri.encodeComponent(e.key);
            if (e.value.isEmpty) {
              return encodedKey; // 空值不添加等号
            }
            return '$encodedKey=${Uri.encodeComponent(e.value)}';
          })
          .join('&');
    }
    //log('[AliyunOSS] CanonicalQueryString: """$canonicalQueryString"""');

    // 6. 构建 CanonicalRequest
    // 格式: HTTP Verb + "\n" + Canonical URI + "\n" + Canonical Query String + "\n" +
    //       Canonical Headers + "\n" + Additional Headers + "\n" + Hashed PayLoad
    // 注意：Canonical Headers 末尾需要有换行符来分隔 Additional Headers
    final canonicalRequest = [
      method.toUpperCase(),
      canonicalUri,
      canonicalQueryString,
      '$canonicalHeadersStr\n', // Headers 末尾换行
      signedHeadersStr, // AdditionalHeaders（末尾无换行，由下一个join添加）
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    //log('[AliyunOSS] CanonicalRequest: """$canonicalRequest"""');

    // 7. 构建 StringToSign
    final canonicalRequestHash = _sha256Hex(canonicalRequest);
    //log('[AliyunOSS] CanonicalRequestHash: $canonicalRequestHash');

    final stringToSign = [
      'OSS4-HMAC-SHA256',
      dateTimeStr,
      '$dateStr/$region/oss/aliyun_v4_request',
      canonicalRequestHash,
    ].join('\n');

    //log('[AliyunOSS] StringToSign: """$stringToSign"""');

    // 8. 计算签名密钥
    // 使用字节进行HMAC计算，确保正确传递二进制数据
    final dateKeyInput = 'aliyun_v4${credential.secretKey}';
    //log('[AliyunOSS] DateKeyInput: $dateKeyInput (长度: ${dateKeyInput.length})');
    final kDateBytes = _hmacSha256Bytes(dateKeyInput, dateStr);
    //log('[AliyunOSS] KDate (hex): ${_bytesToHex(kDateBytes)}');

    final kRegionBytes = _hmacSha256WithBytesKey(kDateBytes, region);
    //log('[AliyunOSS] KRegion (hex): ${_bytesToHex(kRegionBytes)}');

    final kServiceBytes = _hmacSha256WithBytesKey(kRegionBytes, 'oss');
    //log('[AliyunOSS] KService (hex): ${_bytesToHex(kServiceBytes)}');

    final kSigningBytes = _hmacSha256WithBytesKey(
      kServiceBytes,
      'aliyun_v4_request',
    );
    //log('[AliyunOSS] KSigning (hex): ${_bytesToHex(kSigningBytes)}');

    // 9. 计算签名（使用字节key）
    final signature = _hmacSha256WithBytesKeyHex(kSigningBytes, stringToSign);
    //log('[AliyunOSS] Signature: $signature');

    // 10. 构建 Credential
    final credentialStr =
        '${credential.secretId}/$dateStr/$region/oss/aliyun_v4_request';
    //log('[AliyunOSS] Credential: $credentialStr');

    // 11. 构建 Authorization
    final authorization =
        'OSS4-HMAC-SHA256 Credential=$credentialStr,AdditionalHeaders=$signedHeadersStr,Signature=$signature';
    //log('[AliyunOSS] Authorization: $authorization');
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

  /// 获取地域
  String _getRegion() {
    // 阿里云OSS地域格式: cn-hangzhou, cn-beijing 等
    // 从 credential.region 转换
    final region = credential.region;
    if (region.startsWith('oss-')) {
      return region.substring(4); // 移除 'oss-' 前缀
    }
    // 腾讯云格式转换为阿里云格式
    final mapping = {
      'ap-beijing': 'cn-beijing',
      'ap-nanjing': 'cn-nanjing',
      'ap-shanghai': 'cn-shanghai',
      'ap-hangzhou': 'cn-hangzhou',
      'ap-guangzhou': 'cn-guangzhou',
      'ap-shenzhen': 'cn-shenzhen',
      // 常见阿里云地域映射
      'cn-beijing': 'cn-beijing',
      'cn-shanghai': 'cn-shanghai',
      'cn-hangzhou': 'cn-hangzhou',
      'cn-shenzhen': 'cn-shenzhen',
      'cn-guangzhou': 'cn-guangzhou',
      'cn-hongkong': 'cn-hongkong',
    };
    return mapping[region] ?? region;
  }

  /// 获取地域对应的endpoint后缀
  String _getRegionEndpoint() {
    final region = _getRegion();
    // 阿里云地域格式: oss-cn-beijing, oss-cn-shanghai 等
    return 'oss-$region.aliyuncs.com';
  }

  /// 对路径进行 URI 编码（不编码正斜杠）
  /// 阿里云要求：资源路径中的正斜杠 / 不需要编码
  String _encodePath(String path) {
    // 使用 Uri.encodeComponent 编码，然后还原 /
    return Uri.encodeComponent(path).replaceAll('%2F', '/');
  }

  /// HMAC-SHA256 计算，使用字节作为key，返回十六进制字符串（小写）
  String _hmacSha256WithBytesKeyHex(List<int> keyBytes, String data) {
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(dataBytes);
    // Hmac.toString() 返回小写十六进制
    return digest.toString();
  }

  /// 字节列表转十六进制字符串
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// HMAC-SHA256 计算，返回字节（用于签名密钥链计算）
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

  /// SHA256 计算，返回十六进制字符串（小写）
  /// 注意：阿里云 OSS V4 签名使用小写十六进制
  String _sha256Hex(String data) {
    final dataBytes = utf8.encode(data);
    final hash = sha256.convert(dataBytes);
    // sha256.convert().toString() 返回小写十六进制，与阿里云期望一致
    return hash.toString();
  }

  /// 构建请求头（包含签名）
  Map<String, String> _buildHeaders({
    required String method,
    String? bucketName,
    String? objectKey,
    Map<String, String>? extraHeaders,
    Map<String, String>? queryParams,
    String? customHost, // 用于GetService等特殊API
  }) {
    // 使用 ISO8601 格式的日期时间（阿里云V4签名要求）
    final date = DateTime.now().toUtc();
    final iso8601DateTime = _formatIso8601DateTime(date);
    final httpDate = HttpDate.format(date);

    final host = customHost ?? _getHost(bucketName);

    // 注意：不要在这里添加 date header，否则会导致签名不匹配
    // date header 会在签名计算完成后添加（用于HTTP协议兼容性，但不参与签名）
    final headers = <String, String>{
      'host': host,
      'x-oss-date': iso8601DateTime, // 阿里云V4签名要求使用x-oss-date头部（ISO8601格式）
      'x-oss-content-sha256': 'UNSIGNED-PAYLOAD', // 阿里云V4签名要求
      ...?extraHeaders,
    };

    final signature = _getSignatureV4(
      method: method,
      bucketName: bucketName,
      objectKey: objectKey,
      headers: headers,
      queryParams: queryParams,
    );

    // 先添加 Authorization（不包含在签名中）
    headers['Authorization'] = signature;

    // date header 在签名计算后添加（用于HTTP协议兼容性，但不参与签名）
    // 阿里云 OSS V4 签名使用 x-oss-date，时间格式为 ISO8601
    headers['date'] = httpDate;

    return headers;
  }

  /// 获取请求Host
  String _getHost(String? bucketName) {
    final regionEndpoint = _getRegionEndpoint();
    if (bucketName == null) {
      // 列举存储桶时使用地域对应的endpoint
      return regionEndpoint;
    }
    // 访问存储桶时使用 bucketName.endpoint
    return '$bucketName.$regionEndpoint';
  }

  /// 获取存储桶所在地域的Endpoint
  String _getEndpoint(String bucketName) {
    return '$bucketName.${_getRegionEndpoint()}';
  }

  /// 解析阿里云API错误响应
  /// 阿里云OSS错误响应格式（XML）:
  /// ```xml
  /// <Error>
  ///   <Code>AccessDenied</Code>
  ///   <Message>Access Denied</Message>
  ///   <RequestId>xxx</RequestId>
  ///   <HostId>bucket.oss-region.aliyuncs.com</HostId>
  /// </Error>
  /// ```
  String _parseAliyunError(DioException e) {
    final response = e.response;
    if (response == null) {
      return e.message ?? 'Unknown error';
    }

    final statusCode = response.statusCode ?? 0;
    final errorData = response.data;

    if (errorData == null) {
      return 'HTTP $statusCode error: ${e.message}';
    }

    // 使用 xml 包解析错误响应
    try {
      final dataStr = errorData.toString();
      final document = XmlDocument.parse(dataStr);
      final errorElement = document.findElements('Error').first;

      final code = errorElement.findElements('Code').first.innerText;
      final message = errorElement.findElements('Message').first.innerText;
      final requestId = errorElement.findElements('RequestId').first.innerText;
      final hostId = errorElement.findElements('HostId').first.innerText;

      return '阿里云OSS错误 (HTTP $statusCode)\n'
          '  Code: $code\n'
          '  Message: $message\n'
          '  RequestId: $requestId\n'
          '  HostId: $hostId';
    } catch (parseError) {
      // 如果 XML 解析失败，回退到原始方式
      return 'HTTP $statusCode error: $errorData';
    }
  }

  @override
  Future<ApiResponse<List<Bucket>>> listBuckets() async {
    try {
      // 阿里云列举存储桶使用带地域的Endpoint
      // 根据文档示例: Host: oss-cn-hangzhou.aliyuncs.com
      final host = _getHost(null);
      final url = 'https://$host/';

      log('[AliyunOSS] 开始查询存储桶列表, URL: $url');

      final headers = _buildHeaders(method: 'GET', customHost: host);

      log('[AliyunOSS] 发送GET请求...');
      final response = await httpClient.get(url, headers: headers);
      log('[AliyunOSS] 响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = response.data?.toString() ?? '';
        final buckets = _parseBucketsFromXml(responseData);
        log('[AliyunOSS] 解析完成, 共 ${buckets.length} 个存储桶');
        return ApiResponse.success(buckets);
      } else {
        final errorData = response.data?.toString() ?? '';
        logError(
          '[AliyunOSS] 查询存储桶失败, 状态码: ${response.statusCode}, 响应: $errorData',
        );
        return ApiResponse.error(
          'Failed to list buckets, status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseAliyunError(e);
      logError('[AliyunOSS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e, stack) {
      logError('[AliyunOSS] 异常: $e', stack);
      return ApiResponse.error(e.toString());
    }
  }

  List<Bucket> _parseBucketsFromXml(String xml) {
    final buckets = <Bucket>[];

    try {
      final document = XmlDocument.parse(xml);
      // 阿里云GetService API返回的是 ListAllMyBucketsResult
      final rootElement = document.findElements('ListAllMyBucketsResult').first;

      // 解析Buckets下的所有Bucket
      for (final bucketsElement in rootElement.findElements('Buckets')) {
        for (final bucketElement in bucketsElement.findElements('Bucket')) {
          final name = bucketElement.findElements('Name').first.innerText;
          final location = bucketElement
              .findElements('Location')
              .first
              .innerText;
          final creationDateStr = bucketElement
              .findElements('CreationDate')
              .first
              .innerText;

          DateTime? creationDate;
          try {
            creationDate = DateTime.parse(creationDateStr);
          } catch (e) {
            creationDate = null;
          }

          buckets.add(
            Bucket(name: name, region: location, creationDate: creationDate),
          );
        }
      }
    } catch (e) {
      logError('[AliyunOSS] 解析存储桶XML失败: $e');
    }

    return buckets;
  }

  @override
  Future<ApiResponse<ListObjectsResult>> listObjects({
    required String bucketName,
    required String region,
    String prefix = '',
    String delimiter = '/',
    int maxKeys = 1000,
    String? marker,
  }) async {
    try {
      final host = _getEndpoint(bucketName);

      // 构建查询参数
      final queryParams = <String, String>{
        'prefix': prefix,
        'delimiter': delimiter,
        'max-keys': maxKeys.toString(),
      };
      if (marker != null && marker.isNotEmpty) {
        queryParams['marker'] = marker;
      }

      final queryString = queryParams.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');
      final url = 'https://$host/?$queryString';

      log('[AliyunOSS] 开始查询对象列表, URL: $url');

      final headers = _buildHeaders(
        method: 'GET',
        bucketName: bucketName,
        queryParams: queryParams,
      );

      log('[AliyunOSS] 发送GET请求...');
      final response = await httpClient.get(url, headers: headers);

      log('[AliyunOSS] 响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = response.data?.toString() ?? '';
        final result = _parseObjectsFromXml(responseData);
        return ApiResponse.success(result);
      } else {
        final errorData = response.data?.toString() ?? '';
        logError(
          '[AliyunOSS] 查询对象失败, 状态码: ${response.statusCode}, 响应: $errorData',
        );
        return ApiResponse.error(
          'Failed to list objects',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseAliyunError(e);
      logError('[AliyunOSS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e, stack) {
      logError('[AliyunOSS] 异常: $e', stack);
      return ApiResponse.error(e.toString());
    }
  }

  ListObjectsResult _parseObjectsFromXml(String xml) {
    final objects = <ObjectFile>[];

    try {
      final document = XmlDocument.parse(xml);
      final resultElement = document.findElements('ListBucketResult').first;

      // 解析文件内容
      final contentsElements = resultElement.findElements('Contents');

      for (final content in contentsElements) {
        final key = content.findElements('Key').first.innerText;
        final lastModifiedStr = content
            .findElements('LastModified')
            .first
            .innerText;
        final sizeStr = content.findElements('Size').first.innerText;
        final etag = content.findElements('ETag').first.innerText;

        DateTime? lastModified;
        try {
          lastModified = DateTime.parse(lastModifiedStr);
        } catch (e) {
          lastModified = null;
        }

        int? size;
        try {
          size = int.parse(sizeStr);
        } catch (e) {
          size = 0;
        }

        // 从 key 中提取文件名
        final name = key.split('/').where((e) => e.isNotEmpty).lastOrNull ?? '';

        // 判断是文件夹还是文件
        final isFolder = key.endsWith('/');

        objects.add(
          ObjectFile(
            key: key,
            name: name,
            size: size,
            lastModified: lastModified,
            etag: etag.replaceAll('"', ''),
            type: isFolder ? ObjectType.folder : ObjectType.file,
          ),
        );
      }
    } catch (e) {
      logError('[AliyunOSS] 解析对象XML失败: $e');
    }

    return ListObjectsResult(objects: objects);
  }

  @override
  Future<ApiResponse<void>> uploadObject({
    required String bucketName,
    required String region,
    required String objectKey,
    required List<int> data,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final host = _getEndpoint(bucketName);
      final url = 'https://$host/$objectKey';

      log('[AliyunOSS] 开始上传对象: $objectKey');

      // 计算Content-MD5
      final md5Hash = md5.convert(data);
      final contentMd5 = base64Encode(md5Hash.bytes);

      // 生成 GMT 格式的 Date 头部和 ISO8601 格式的 x-oss-date
      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final headers = {
        'Authorization': '',
        'Content-Type': 'application/octet-stream',
        'Content-MD5': contentMd5,
        'date': httpDate,
        'x-oss-date': iso8601DateTime, // 阿里云V4签名要求
        'host': _getEndpoint(bucketName),
      };

      // 生成签名
      final signature = _getSignatureV4(
        method: 'PUT',
        bucketName: bucketName,
        objectKey: objectKey,
        headers: headers,
      );
      headers['Authorization'] = signature;

      final response = await httpClient.put(
        url,
        data: data,
        headers: headers,
        onSendProgress: onProgress,
      );

      if (response.statusCode == 200) {
        log('[AliyunOSS] 上传成功');
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error(
          'Failed to upload object',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseAliyunError(e);
      logError('[AliyunOSS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
      logError('[AliyunOSS] 上传异常: $e');
      return ApiResponse.error(e.toString());
    }
  }

  @override
  Future<ApiResponse<List<int>>> downloadObject({
    required String bucketName,
    required String region,
    required String objectKey,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final host = _getEndpoint(bucketName);
      final url = 'https://$host/$objectKey';

      log('[AliyunOSS] 开始下载对象: $objectKey');

      final headers = _buildHeaders(
        method: 'GET',
        bucketName: bucketName,
        objectKey: objectKey,
      );

      final response = await httpClient.get(
        url,
        headers: headers,
        onReceiveProgress: onProgress,
        responseType: ResponseType.bytes,
      );

      if (response.statusCode == 200) {
        log('[AliyunOSS] 下载成功');
        return ApiResponse.success(response.data);
      } else {
        return ApiResponse.error(
          'Failed to download object',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseAliyunError(e);
      logError('[AliyunOSS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
      logError('[AliyunOSS] 下载异常: $e');
      return ApiResponse.error(e.toString());
    }
  }

  @override
  Future<ApiResponse<void>> deleteObject({
    required String bucketName,
    required String region,
    required String objectKey,
  }) async {
    try {
      final host = _getEndpoint(bucketName);
      final url = 'https://$host/$objectKey';

      log('[AliyunOSS] 开始删除对象: $objectKey');

      final headers = _buildHeaders(
        method: 'DELETE',
        bucketName: bucketName,
        objectKey: objectKey,
      );

      final response = await httpClient.delete(url, headers: headers);

      if (response.statusCode == 204 || response.statusCode == 200) {
        log('[AliyunOSS] 删除成功');
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error(
          'Failed to delete object',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseAliyunError(e);
      logError('[AliyunOSS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
      logError('[AliyunOSS] 删除异常: $e');
      return ApiResponse.error(e.toString());
    }
  }

  @override
  Future<ApiResponse<void>> deleteObjects({
    required String bucketName,
    required String region,
    required List<String> objectKeys,
  }) async {
    // 阿里云OSS支持批量删除，通过POST请求到 /?delete
    try {
      final host = _getEndpoint(bucketName);
      final url = 'https://$host/?delete';

      log('[AliyunOSS] 开始批量删除对象: ${objectKeys.length} 个文件');

      // 构建批量删除请求体
      final deleteXml = StringBuffer();
      deleteXml.write('<?xml version="1.0" encoding="UTF-8"?>');
      deleteXml.write('<Delete>');
      deleteXml.write('<Quiet>true</Quiet>');
      for (final key in objectKeys) {
        deleteXml.write('<Object><Key>$key</Key></Object>');
      }
      deleteXml.write('</Delete>');

      final requestBody = deleteXml.toString();
      final requestBodyBytes = utf8.encode(requestBody);

      // 计算Content-MD5
      final md5Hash = md5.convert(requestBodyBytes);
      final contentMd5 = base64Encode(md5Hash.bytes);

      // 生成 GMT 格式的 Date 头部和 ISO8601 格式的 x-oss-date
      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final headers = {
        'Authorization': '',
        'Content-Type': 'application/xml',
        'Content-MD5': contentMd5,
        'date': httpDate,
        'x-oss-date': iso8601DateTime, // 阿里云V4签名要求
        'host': _getEndpoint(bucketName),
      };

      // 生成签名
      final signature = _getSignatureV4(
        method: 'POST',
        bucketName: bucketName,
        objectKey: '?delete',
        headers: headers,
      );
      headers['Authorization'] = signature;

      final response = await httpClient.post(
        url,
        data: requestBodyBytes,
        headers: headers,
      );

      if (response.statusCode == 200) {
        log('[AliyunOSS] 批量删除成功');
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error(
          'Failed to delete objects',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseAliyunError(e);
      logError('[AliyunOSS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
      logError('[AliyunOSS] 批量删除异常: $e');
      return ApiResponse.error(e.toString());
    }
  }

  @override
  Future<ApiResponse<void>> uploadObjectMultipart({
    required String bucketName,
    required String region,
    required String objectKey,
    required File file,
    int chunkSize = 64 * 1024 * 1024,
    void Function(int sent, int total)? onProgress,
    void Function(int status)? onStatusChanged,
  }) async {
    try {
      log('[AliyunOSS] 开始分块上传: ${file.path} -> $objectKey');

      final host = _getEndpoint(bucketName);
      final objectPath = '/$objectKey';

      // 1. 初始化分块上传
      final initUrl = 'https://$host$objectPath?uploads';

      final initHeaders = _buildHeaders(
        method: 'POST',
        bucketName: bucketName,
        objectKey: objectKey,
        extraHeaders: {'Content-Type': 'application/xml'},
      );

      log('[AliyunOSS] 初始化分块上传...');
      final initResponse = await httpClient.post(initUrl, headers: initHeaders);

      if (initResponse.statusCode != 200) {
        return ApiResponse.error(
          'Failed to initiate multipart upload',
          statusCode: initResponse.statusCode,
        );
      }

      // 解析UploadId
      final responseData = initResponse.data?.toString() ?? '';
      String? uploadId;
      try {
        final document = XmlDocument.parse(responseData);
        uploadId = document.findElements('UploadId').first.innerText;
      } catch (e) {
        logError('[AliyunOSS] 解析UploadId失败: $e');
        return ApiResponse.error('Failed to parse UploadId');
      }

      log('[AliyunOSS] 获取到UploadId: $uploadId');

      // 2. 使用FileChunkReader分块读取并上传
      final fileSize = await file.length();
      final uploadedParts = <Map<String, dynamic>>[];

      final chunkReader = FileChunkReader(chunkSize: chunkSize);
      await chunkReader.streamChunks(
        file,
        onChunk: (chunk) async {
          if (onStatusChanged != null) {
            onStatusChanged(1); // 1: Uploading
          }

          final partNumber = chunk.partNumber;

          // 计算当前块的MD5
          final md5Hash = md5.convert(chunk.data);
          final contentMd5 = base64Encode(md5Hash.bytes);

          // 上传单个分块
          final uploadUrl =
              'https://$host$objectPath?partNumber=$partNumber&uploadId=$uploadId';

          final uploadHeaders = _buildHeaders(
            method: 'PUT',
            bucketName: bucketName,
            objectKey: objectKey,
            extraHeaders: {
              'Content-Type': 'application/octet-stream',
              'Content-MD5': contentMd5,
            },
            queryParams: {
              'partNumber': partNumber.toString(),
              'uploadId': uploadId!,
            },
          );

          final uploadResponse = await httpClient.put(
            uploadUrl,
            data: chunk.data,
            headers: uploadHeaders,
          );

          if (uploadResponse.statusCode == 200) {
            // 记录已上传的分块信息
            final etag = uploadResponse.headers['etag']?.first ?? '';
            uploadedParts.add({
              'PartNumber': partNumber,
              'ETag': etag.replaceAll('"', ''),
            });

            onProgress?.call(chunk.offset + chunk.size, fileSize);
            log('[AliyunOSS] 分块 $partNumber 上传成功');
          } else {
            logError(
              '[AliyunOSS] 分块 $partNumber 上传失败: ${uploadResponse.statusCode}',
            );
            throw ApiResponse.error(
              'Failed to upload part $partNumber',
              statusCode: uploadResponse.statusCode,
            );
          }
        },
        onProgress: (bytesRead, totalBytes) {
          onProgress?.call(bytesRead, totalBytes);
        },
      );

      // 3. 完成分块上传
      if (onStatusChanged != null) {
        onStatusChanged(2); // 2: Completing
      }

      log('[AliyunOSS] 开始完成分块上传...');

      // 按PartNumber排序
      uploadedParts.sort((a, b) => a['PartNumber'].compareTo(b['PartNumber']));

      // 构建完成请求体
      final completeXml = StringBuffer();
      completeXml.write('<?xml version="1.0" encoding="UTF-8"?>');
      completeXml.write('<CompleteMultipartUpload>');
      for (final part in uploadedParts) {
        completeXml.write('<Part>');
        completeXml.write('<PartNumber>${part['PartNumber']}</PartNumber>');
        completeXml.write('<ETag>${part['ETag']}</ETag>');
        completeXml.write('</Part>');
      }
      completeXml.write('</CompleteMultipartUpload>');

      final completeUrl = 'https://$host$objectPath?uploadId=$uploadId';
      final completeBody = completeXml.toString();
      final completeBodyBytes = utf8.encode(completeBody);

      // 计算Content-MD5
      final completeMd5 = md5.convert(completeBodyBytes);
      final completeMd5Str = base64Encode(completeMd5.bytes);

      final completeHeaders = _buildHeaders(
        method: 'POST',
        bucketName: bucketName,
        objectKey: objectKey,
        extraHeaders: {
          'Content-Type': 'application/xml',
          'Content-MD5': completeMd5Str,
        },
        queryParams: {'uploadId': uploadId},
      );

      final completeResponse = await httpClient.post(
        completeUrl,
        data: completeBodyBytes,
        headers: completeHeaders,
      );

      if (completeResponse.statusCode == 200) {
        log('[AliyunOSS] 分块上传完成');
        if (onStatusChanged != null) {
          onStatusChanged(3); // 3: Completed
        }
        return ApiResponse.success(null);
      } else {
        logError('[AliyunOSS] 完成分块上传失败: ${completeResponse.statusCode}');
        return ApiResponse.error(
          'Failed to complete multipart upload',
          statusCode: completeResponse.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseAliyunError(e);
      logError('[AliyunOSS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e, stack) {
      if (e is ApiResponse) {
        return e;
      }
      logError('[AliyunOSS] 分块上传异常: $e', stack);
      return ApiResponse.error(e.toString());
    }
  }
}
