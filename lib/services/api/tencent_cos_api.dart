import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../../models/bucket.dart';
import '../../models/object_file.dart';
import '../../models/platform_credential.dart';
import 'cloud_platform_api.dart';
import 'http_client.dart';

class TencentCosApi implements ICloudPlatformApi {
  final PlatformCredential credential;
  final HttpClient httpClient;

  TencentCosApi(this.credential, this.httpClient);

  /// 生成腾讯云COS签名
  ///
  /// [method] HTTP方法
  /// [path] 请求路径
  /// [headers] 请求头
  /// [secretId] 密钥ID
  /// [secretKey] 密钥
  String _getSignature(
    String method,
    String path,
    Map<String, String> headers,
    String secretId,
    String secretKey,
  ) {
    // 生成签名时间（当前时间戳，有效期1小时）
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final end = now + 3600;
    final keyTime = '$now;$end'; // 完整的时间范围格式：start;end

    // 1. 计算 SignKey = HMAC-SHA1(SecretKey, KeyTime)
    // SignKey 是十六进制小写字符串
    final signKey = _hmacSha1(secretKey, keyTime);

    // 2. 计算 CanonicalRequest 的 SHA1 哈希
    final canonicalRequest = _buildCanonicalRequest(method, path, headers);
    final sha1CanonicalRequest = sha1.convert(utf8.encode(canonicalRequest));

    // 3. 拼接 StringToSign = "sha1\n{q-sign-time}\n{SHA1(CanonicalRequest)}\n"
    final stringToSign = 'sha1\n$keyTime\n${sha1CanonicalRequest.toString()}\n';

    // 4. 计算 Signature = HMAC-SHA1(SignKey, StringToSign)
    // SignKey 作为十六进制字符串，需要转换为字节后作为 HMAC 密钥
    final signatureHex = _hmacSha1WithHexKey(signKey, stringToSign);

    return signatureHex;
  }

  /// HMAC-SHA1 计算，返回十六进制字符串
  String _hmacSha1(String key, String data) {
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha1, keyBytes);
    final digest = hmac.convert(dataBytes);
    return digest.toString();
  }

  /// HMAC-SHA1 计算，SignKey 为十六进制字符串（作为字符串使用，非字节）
  /// 腾讯云文档说明：SignKey 为密钥（字符串形式，非原始二进制）
  String _hmacSha1WithHexKey(String hexKey, String data) {
    // SignKey 作为字符串传递给 HMAC（不是转换为字节）
    final keyBytes = utf8.encode(hexKey);
    final dataBytes = utf8.encode(data);
    final hmac = Hmac(sha1, keyBytes);
    final digest = hmac.convert(dataBytes);
    return digest.toString();
  }

  /// 构建规范请求 (CanonicalRequest)
  ///
  /// 格式: HttpMethod\nUriPathname\nHttpParameters\nHttpHeaders\n
  String _buildCanonicalRequest(
    String method,
    String path,
    Map<String, String> headers,
  ) {
    // 1. HttpMethod 转小写
    final httpMethod = method.toLowerCase();

    // 2. UriPathname
    final uriPathname = path;

    // 3. HttpParameters (URL参数)
    final httpParameters = '';

    // 4. HttpHeaders (参与签名的头部，按key字典序排序)
    // key 使用小写并 URL 编码，value 使用 URL 编码
    final sortedHeaders = headers.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    final httpHeaders = sortedHeaders.map((e) {
      final key = _urlEncode(e.key.toLowerCase());
      final value = _urlEncode(e.value);
      return '$key=$value';
    }).join('&');

    // 拼接: HttpMethod\nUriPathname\nHttpParameters\nHttpHeaders\n
    return '$httpMethod\n$uriPathname\n$httpParameters\n$httpHeaders\n';
  }

  /// URL 编码（只编码必要的字符，保留字母数字和 -_.~）
  String _urlEncode(String value) {
    return Uri.encodeComponent(value);
  }

  @override
  Future<ApiResponse<List<Bucket>>> listBuckets() async {
    try {
      // 使用 service.cos.myqcloud.com 查询所有存储桶（不指定地域）
      final url = 'https://service.cos.myqcloud.com/';
      final host = 'service.cos.myqcloud.com';
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      // 生成签名时需要包含 Host 和 Date 头部（按字典序排序）
      final headersForSign = {'date': date, 'host': host};
      final signature = _getSignature(
        'GET',
        '/',
        headersForSign,
        credential.secretId,
        credential.secretKey,
      );

      // 生成 headerList 和 urlParamList 用于 Authorization（按字典序排序）
      final headerList = 'date;host';
      final urlParamList = '';

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=$headerList&q-url-param-list=$urlParamList&q-signature=$signature',
        'Content-Type': 'application/xml',
        'Host': host,
        'Date': date,
      };

      final response = await httpClient.get(url, headers: headers);
      if (response.statusCode == 200) {
        // 解析XML响应，提取存储桶列表
        final buckets = _parseBucketsFromXml(response.data);
        return ApiResponse.success(buckets);
      } else {
        return ApiResponse.error(
          'Failed to list buckets',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseTencentCloudError(e);
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  List<Bucket> _parseBucketsFromXml(String xml) {
    // 简化的XML解析，实际需要使用xml包
    final buckets = <Bucket>[];
    // 假设解析逻辑
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
      final host = '$bucketName.cos.$region.myqcloud.com';
      final url =
          'https://$host/?prefix=$prefix&delimiter=$delimiter&max-keys=$maxKeys${marker != null ? '&marker=$marker' : ''}';
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成签名时需要包含 Host 头部
      final headersForSign = {'host': host};
      final signature = _getSignature(
        'GET',
        '/?prefix=$prefix&delimiter=$delimiter&max-keys=$maxKeys${marker != null ? '&marker=$marker' : ''}',
        headersForSign,
        credential.secretId,
        credential.secretKey,
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=host&q-url-param-list=&q-signature=$signature',
        'Host': host,
      };

      final response = await httpClient.get(url, headers: headers);
      if (response.statusCode == 200) {
        final result = _parseObjectsFromXml(response.data);
        return ApiResponse.success(result);
      } else {
        return ApiResponse.error(
          'Failed to list objects',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseTencentCloudError(e);
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  ListObjectsResult _parseObjectsFromXml(String xml) {
    // 解析XML，提取对象列表
    final objects = <ObjectFile>[];
    // 假设解析逻辑
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
      final host = '$bucketName.cos.$region.myqcloud.com';
      final url = 'https://$host/$objectKey';
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成签名时需要包含 Host 头部
      final headersForSign = {'host': host};
      final signature = _getSignature(
        'PUT',
        '/$objectKey',
        headersForSign,
        credential.secretId,
        credential.secretKey,
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=host&q-url-param-list=&q-signature=$signature',
        'Content-Type': 'application/octet-stream',
        'Host': host,
      };

      final response = await httpClient.put(
        url,
        data: data,
        headers: headers,
        onSendProgress: onProgress,
      );
      if (response.statusCode == 200) {
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error(
          'Failed to upload object',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseTencentCloudError(e);
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
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
      final host = '$bucketName.cos.$region.myqcloud.com';
      final url = 'https://$host/$objectKey';
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成签名时需要包含 Host 头部
      final headersForSign = {'host': host};
      final signature = _getSignature(
        'GET',
        '/$objectKey',
        headersForSign,
        credential.secretId,
        credential.secretKey,
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=host&q-url-param-list=&q-signature=$signature',
        'Host': host,
      };

      final response = await httpClient.get(
        url,
        headers: headers,
        onReceiveProgress: onProgress,
      );
      if (response.statusCode == 200) {
        return ApiResponse.success(response.data);
      } else {
        return ApiResponse.error(
          'Failed to download object',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseTencentCloudError(e);
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
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
      final host = '$bucketName.cos.$region.myqcloud.com';
      final url = 'https://$host/$objectKey';
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成签名时需要包含 Host 头部
      final headersForSign = {'host': host};
      final signature = _getSignature(
        'DELETE',
        '/$objectKey',
        headersForSign,
        credential.secretId,
        credential.secretKey,
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=host&q-url-param-list=&q-signature=$signature',
        'Host': host,
      };

      final response = await httpClient.delete(url, headers: headers);
      if (response.statusCode == 204) {
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error(
          'Failed to delete object',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseTencentCloudError(e);
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  @override
  Future<ApiResponse<void>> deleteObjects({
    required String bucketName,
    required String region,
    required List<String> objectKeys,
  }) async {
    // 腾讯云支持批量删除，但这里简化实现逐个删除
    for (final key in objectKeys) {
      final result = await deleteObject(
        bucketName: bucketName,
        region: region,
        objectKey: key,
      );
      if (!result.success) {
        return result;
      }
    }
    return ApiResponse.success(null);
  }

  /// 解析腾讯云API错误响应
  /// 腾讯云COS错误响应格式（XML）:
  /// ```xml
  /// <Error>
  ///   <Code>AuthFailure</Code>
  ///   <Message>签名失败...</Message>
  ///   <Resource>cos.ap-beijing.myqcloud.com/</Resource>
  ///   <RequestId>xxx</RequestId>
  /// </Error>
  /// ```
  String _parseTencentCloudError(DioException e) {
    final response = e.response;
    if (response == null) {
      return e.message ?? 'Unknown error';
    }

    final statusCode = response.statusCode ?? 0;
    final errorData = response.data;

    if (errorData == null) {
      return 'HTTP $statusCode error: ${e.message}';
    }

    // 尝试从XML中提取错误信息
    final dataStr = errorData.toString();

    // 提取 Code
    final codeMatch = RegExp(r'<Code>([^<]+)</Code>').firstMatch(dataStr);
    final code = codeMatch?.group(1);

    // 提取 Message
    final messageMatch = RegExp(
      r'<Message>([^<]+)</Message>',
    ).firstMatch(dataStr);
    final message = messageMatch?.group(1);

    // 提取 Resource
    final resourceMatch = RegExp(
      r'<Resource>([^<]+)</Resource>',
    ).firstMatch(dataStr);
    final resource = resourceMatch?.group(1);

    // 提取 RequestId
    final requestIdMatch = RegExp(
      r'<RequestId>([^<]+)</RequestId>',
    ).firstMatch(dataStr);
    final requestId = requestIdMatch?.group(1);

    // 构建错误描述
    final buffer = StringBuffer();
    buffer.write('腾讯云API错误 (HTTP $statusCode)');

    if (code != null) {
      buffer.write('\n  Code: $code');
    }
    if (message != null) {
      buffer.write('\n  Message: $message');
    }
    if (resource != null) {
      buffer.write('\n  Resource: $resource');
    }
    if (requestId != null) {
      buffer.write('\n  RequestId: $requestId');
    }

    return buffer.toString();
  }
}
