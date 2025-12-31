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
import '../multipart_upload/multipart_upload_manager.dart';

class TencentCosApi implements ICloudPlatformApi {
  /// 控制签名生成过程日志的打印开关
  static const bool _debugSignature = false;

  final PlatformCredential credential;
  late final Dio _dio;

  TencentCosApi(this.credential) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
  }

  /// 打印签名调试日志（仅在_debugSignature为true时打印）
  void _debugLog(String message) {
    if (_debugSignature) {
      log(message);
    }
  }

  /// 生成腾讯云COS签名
  ///
  /// [method] HTTP方法
  /// [path] 请求路径（不含查询参数）
  /// [headers] 请求头
  /// [queryParams] 查询参数（可选）
  /// [secretId] 密钥ID
  /// [secretKey] 密钥
  String _getSignature(
    String method,
    String path,
    Map<String, String> headers, {
    Map<String, String>? queryParams,
    required String secretId,
    required String secretKey,
  }) {
    // 生成签名时间（当前时间戳，有效期1小时）
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final end = now + 3600;
    final keyTime = '$now;$end'; // 完整的时间范围格式：start;end

    _debugLog('[TencentCOS] 签名 KeyTime: $keyTime');

    // 1. 计算 SignKey = HMAC-SHA1(SecretKey, KeyTime)
    // SignKey 是十六进制小写字符串
    final signKey = _hmacSha1(secretKey, keyTime);
    _debugLog('[TencentCOS] 签名 SignKey: $signKey');

    // 2. 计算 CanonicalRequest 的 SHA1 哈希
    final canonicalRequest = _buildCanonicalRequest(
      method,
      path,
      headers,
      queryParams: queryParams,
    );
    final sha1CanonicalRequest = sha1.convert(utf8.encode(canonicalRequest));
    _debugLog('[TencentCOS] 签名 CanonicalRequest SHA1: ${sha1CanonicalRequest.toString()}');

    // 3. 拼接 StringToSign = "sha1\n{q-sign-time}\n{SHA1(CanonicalRequest)}\n"
    final stringToSign = 'sha1\n$keyTime\n${sha1CanonicalRequest.toString()}\n';
    _debugLog('[TencentCOS] 签名 StringToSign: $stringToSign');

    // 4. 计算 Signature = HMAC-SHA1(SignKey, StringToSign)
    // SignKey 作为十六进制字符串，需要转换为字节后作为 HMAC 密钥
    final signatureHex = _hmacSha1WithHexKey(signKey, stringToSign);
    _debugLog('[TencentCOS] 签名最终 Signature: $signatureHex');

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
    Map<String, String> headers, {
    Map<String, String>? queryParams,
  }) {
    // 1. HttpMethod 转小写
    final httpMethod = method.toLowerCase();

    // 2. UriPathname (不含查询参数)
    final uriPathname = path;

    // 3. HttpParameters (URL参数)
    String httpParameters = '';
    if (queryParams != null && queryParams.isNotEmpty) {
      // 对参数进行排序和编码
      final sortedParams = queryParams.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

      // 生成 HttpParameters: key1=value1&key2=value2
      // 注意：等号不编码，这是腾讯云的要求
      // 使用 encodeComponent，但圆括号需要额外编码
      httpParameters = sortedParams
          .map((e) {
            final key = Uri.encodeComponent(e.key.toLowerCase());
            final value = _encodeMarkerValue(e.value);
            return '$key=$value';
          })
          .join('&');
    }

    log('[TencentCOS] CanonicalRequest HttpParameters: $httpParameters');

    // 4. HttpHeaders (参与签名的头部，按key字典序排序)
    // key 使用小写并 URL 编码，value 使用 URL 编码
    // headers 必须使用 encodeComponent，逗号等需要编码
    final sortedHeaders = headers.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    final httpHeaders = sortedHeaders
        .map((e) {
          final key = Uri.encodeComponent(e.key.toLowerCase());
          final value = Uri.encodeComponent(e.value);
          return '$key=$value';
        })
        .join('&');

    log('[TencentCOS] CanonicalRequest HttpHeaders: $httpHeaders');

    // 拼接: HttpMethod\nUriPathname\nHttpParameters\nHttpHeaders\n
    final canonicalRequest = '$httpMethod\n$uriPathname\n$httpParameters\n$httpHeaders\n';
    log('[TencentCOS] CanonicalRequest完整: $canonicalRequest');

    return canonicalRequest;
  }

  /// URL 编码（用于 queryParams 编码，圆括号等特殊字符也需要编码）
  String _urlEncode(String value) {
    return Uri.encodeComponent(value);
  }

  /// marker 值的特殊编码：encodeComponent 基础上额外编码圆括号
  String _encodeMarkerValue(String value) {
    // 先用 encodeComponent 编码基础字符
    String encoded = Uri.encodeComponent(value);
    // 额外编码圆括号 ( -> %28, ) -> %29
    encoded = encoded.replaceAll('(', '%28').replaceAll(')', '%29');
    return encoded;
  }

  @override
  Future<ApiResponse<List<Bucket>>> listBuckets() async {
    try {
      // 使用 service.cos.myqcloud.com 查询所有存储桶（不指定地域）
      final url = 'https://service.cos.myqcloud.com/';
      final host = 'service.cos.myqcloud.com';
      log('[TencentCOS] 开始查询存储桶列表, URL: $url');

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      log('[TencentCOS] 生成签名, Date: $date, Host: $host');

      // 生成签名时需要包含 Host 和 Date 头部（按字典序排序）
      final headersForSign = {'date': date, 'host': host};
      final signature = _getSignature(
        'GET',
        '/',
        headersForSign,
        secretId: credential.secretId,
        secretKey: credential.secretKey,
      );

      log('[TencentCOS] 签名生成完成, Signature: $signature');

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

      log('[TencentCOS] 发送GET请求...');
      final response = await _dio.get(url, options: Options(headers: headers));
      log('[TencentCOS] 响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = response.data?.toString() ?? '';
        //log('[TencentCOS] 原始响应数据: $responseData');

        // 解析XML响应，提取存储桶列表
        final buckets = _parseBucketsFromXml(responseData);
        log('[TencentCOS] 解析完成, 共 ${buckets.length} 个存储桶');
        return ApiResponse.success(buckets);
      } else {
        final errorData = response.data?.toString() ?? '';
        logError(
          '[TencentCOS] 查询存储桶失败, 状态码: ${response.statusCode}, 响应: $errorData',
        );
        return ApiResponse.error(
          'Failed to list buckets, status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseTencentCloudError(e);
      logError('[TencentCOS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e, stack) {
      logError('[TencentCOS] 异常: $e', stack);
      return ApiResponse.error(e.toString());
    }
  }

  List<Bucket> _parseBucketsFromXml(String xml) {
    final buckets = <Bucket>[];

    // 使用 xml 包解析
    final document = XmlDocument.parse(xml);
    final bucketsElement = document
        .findElements('ListAllMyBucketsResult')
        .first;
    final bucketsList = bucketsElement.findElements('Buckets').first;
    final bucketElements = bucketsList.findElements('Bucket');

    for (final bucketElement in bucketElements) {
      final name = bucketElement.findElements('Name').first.innerText;
      final region = bucketElement.findElements('Location').first.innerText;
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
        Bucket(name: name, region: region, creationDate: creationDate),
      );
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
      final host = '$bucketName.cos.$region.myqcloud.com';

      // 构建查询参数（签名中使用原始值）
      final queryParams = <String, String>{};
      if (prefix.isNotEmpty) queryParams['prefix'] = prefix;
      if (delimiter.isNotEmpty) queryParams['delimiter'] = delimiter;
      queryParams['max-keys'] = maxKeys.toString();
      if (marker != null) queryParams['marker'] = marker;

      // 手动构建URL，确保签名和实际请求编码一致
      // marker 值需要特殊编码（圆括号）
      final sortedParams = queryParams.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      final queryString = sortedParams
          .map((e) {
            final key = Uri.encodeComponent(e.key);
            final value = e.key.toLowerCase() == 'marker'
                ? _encodeMarkerValue(e.value)
                : Uri.encodeComponent(e.value);
            return '$key=$value';
          })
          .join('&');
      final url = 'https://$host/?$queryString';

      log('[TencentCOS] 开始查询对象列表, URL: $url');
      log('[TencentCOS] QueryString: $queryString');

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      // 生成签名时需要包含 Host 和 Date 头部
      final headersForSign = {'host': host, 'date': date};
      final signature = _getSignature(
        'GET',
        '/',
        headersForSign,
        queryParams: queryParams,
        secretId: credential.secretId,
        secretKey: credential.secretKey,
      );

      // 生成 headerList 和 urlParamList（按字典序排序）
      final headerList = 'date;host';
      final sortedParamKeys =
          queryParams.keys.map((k) => _urlEncode(k.toLowerCase())).toList()
            ..sort();
      final urlParamList = sortedParamKeys.join(';');

      log(
        '[TencentCOS] 签名生成完成, HeaderList: $headerList, UrlParamList: $urlParamList',
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000};${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}&q-key-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000};${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}&q-header-list=$headerList&q-url-param-list=$urlParamList&q-signature=$signature',
        'Host': host,
        'Date': date,
      };

      log('[TencentCOS] 发送GET请求...');
      // 直接使用完整 URL，避免 Dio 重新编码
      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      log('[TencentCOS] 响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = response.data?.toString() ?? '';
        //log('[TencentCOS] 原始响应数据: $responseData');
        final result = _parseObjectsFromXml(responseData);
        return ApiResponse.success(result);
      } else {
        final errorData = response.data?.toString() ?? '';
        logError(
          '[TencentCOS] 查询对象失败, 状态码: ${response.statusCode}, 响应: $errorData',
        );
        return ApiResponse.error(
          'Failed to list objects',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      // 输出完整的错误响应数据用于调试
      final errorData = e.response?.data?.toString() ?? '';
      logError('[TencentCOS] DioException 原始响应: $errorData');
      final errorDetail = _parseTencentCloudError(e);
      logError('[TencentCOS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e, stack) {
      logError('[TencentCOS] 异常: $e', stack);
      return ApiResponse.error(e.toString());
    }
  }

  ListObjectsResult _parseObjectsFromXml(String xml) {
    // 使用 xml 包解析
    final document = XmlDocument.parse(xml);
    final resultElement = document.findElements('ListBucketResult').first;

    final objects = <ObjectFile>[];
    bool isTruncated = false;
    String? nextMarker;

    // 解析分页信息
    try {
      final isTruncatedElement = resultElement.findElements('IsTruncated').first;
      isTruncated = isTruncatedElement.innerText.toLowerCase() == 'true';
      log('[TencentCOS] IsTruncated: $isTruncated');
    } catch (e) {
      isTruncated = false;
    }

    try {
      final nextMarkerElement = resultElement.findElements('NextMarker').first;
      nextMarker = nextMarkerElement.innerText;
      log('[TencentCOS] NextMarker: $nextMarker');
    } catch (e) {
      nextMarker = null;
    }

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
          etag: etag,
          type: isFolder ? ObjectType.folder : ObjectType.file,
        ),
      );
    }

    return ListObjectsResult(
      objects: objects,
      isTruncated: isTruncated,
      nextMarker: nextMarker,
    );
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

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      // 生成签名时需要包含 Host 和 Date 头部
      final headersForSign = {'host': host, 'date': date};
      final signature = _getSignature(
        'PUT',
        '/$objectKey',
        headersForSign,
        secretId: credential.secretId,
        secretKey: credential.secretKey,
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=date;host&q-url-param-list=&q-signature=$signature',
        'Content-Type': 'application/octet-stream',
        'Host': host,
        'Date': date,
      };

      final response = await _dio.put(
        url,
        data: data,
        options: Options(headers: headers),
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

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      // 生成签名时需要包含 Host 和 Date 头部
      final headersForSign = {'host': host, 'date': date};
      final signature = _getSignature(
        'GET',
        '/$objectKey',
        headersForSign,
        secretId: credential.secretId,
        secretKey: credential.secretKey,
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=date;host&q-url-param-list=&q-signature=$signature',
        'Host': host,
        'Date': date,
      };

      final response = await _dio.get(
        url,
        options: Options(headers: headers, responseType: ResponseType.bytes),
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

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      // 生成签名时需要包含 Host 和 Date 头部
      final headersForSign = {'host': host, 'date': date};
      final signature = _getSignature(
        'DELETE',
        '/$objectKey',
        headersForSign,
        secretId: credential.secretId,
        secretKey: credential.secretKey,
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=date;host&q-url-param-list=&q-signature=$signature',
        'Host': host,
        'Date': date,
      };

      final response = await _dio.delete(url, options: Options(headers: headers));
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

  @override
  Future<ApiResponse<void>> createFolder({
    required String bucketName,
    required String region,
    required String folderName,
    String prefix = '',
  }) async {
    try {
      // 构建文件夹的key：prefix + folderName + /
      final objectKey = prefix.isEmpty ? '$folderName/' : '$prefix$folderName/';
      final host = '$bucketName.cos.$region.myqcloud.com';
      final url = 'https://$host/$objectKey';
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      // 生成签名时需要包含 Host 和 Date 头部
      final headersForSign = {'host': host, 'date': date};
      final signature = _getSignature(
        'PUT',
        '/$objectKey',
        headersForSign,
        secretId: credential.secretId,
        secretKey: credential.secretKey,
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=date;host&q-url-param-list=&q-signature=$signature',
        'Content-Type': 'application/directory',
        'Host': host,
        'Date': date,
      };

      log('[TencentCOS] 创建文件夹: $objectKey');
      final response = await _dio.put(
        url,
        data: <int>[],
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        log('[TencentCOS] 文件夹创建成功: $objectKey');
        return ApiResponse.success(null);
      } else {
        logError('[TencentCOS] 创建文件夹失败: ${response.statusCode}');
        return ApiResponse.error(
          'Failed to create folder',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      final errorDetail = _parseTencentCloudError(e);
      logError('[TencentCOS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e, stack) {
      logError('[TencentCOS] 异常: $e', stack);
      return ApiResponse.error(e.toString());
    }
  }

  @override
  Future<ApiResponse<void>> uploadObjectMultipart({
    required String bucketName,
    required String region,
    required String objectKey,
    required File file,
    int chunkSize = 64 * 1024 * 1024, // 64MB 分块
    void Function(int sent, int total)? onProgress,
    void Function(int status)? onStatusChanged,
  }) async {
    try {
      log('[TencentCOS] 开始分块上传: ${file.path} -> $objectKey');

      final manager = MultipartUploadManager(
        credential: credential,
        dio: _dio,
        bucketName: bucketName,
        region: region,
        objectKey: objectKey,
        chunkSize: chunkSize,
      );

      // 设置签名回调，复用 TencentCosApi 的签名方法
      manager.getSignature = (method, path, {queryParams}) async {
        final date = HttpDate.format(DateTime.now().toUtc());
        // 注意：Date 头部保持原始格式，不要转小写；Host 需要转小写
        // 对于 uploadPart 请求，还需要包含 content-length 和 content-md5
        final headersForSign = {
          'host': '$bucketName.cos.$region.myqcloud.com'.toLowerCase(),
          'date': date,
        };
        return _getSignature(
          method,
          path,
          headersForSign,
          queryParams: queryParams,
          secretId: credential.secretId,
          secretKey: credential.secretKey,
        );
      };

      // 设置签名回调（带额外头部，用于 uploadPart）
      manager.getSignatureWithHeaders =
          (method, path, extraHeaders, {queryParams}) async {
            final date = HttpDate.format(DateTime.now().toUtc());
            // 基础头部
            final headersForSign = {
              'host': '$bucketName.cos.$region.myqcloud.com'.toLowerCase(),
              'date': date,
            };
            // 合并额外头部
            headersForSign.addAll(extraHeaders);
            return _getSignature(
              method,
              path,
              headersForSign,
              queryParams: queryParams,
              secretId: credential.secretId,
              secretKey: credential.secretKey,
            );
          };

      // 设置状态回调
      if (onStatusChanged != null) {
        manager.onStatusChanged = (status) {
          onStatusChanged(status.index);
        };
      }

      // 上传文件
      final success = await manager.uploadFile(
        file,
        onProgress: (bytesUploaded, totalBytes) {
          onProgress?.call(bytesUploaded, totalBytes);
        },
      );

      if (success) {
        log('[TencentCOS] 分块上传成功');
        return ApiResponse.success(null);
      } else {
        logError('[TencentCOS] 分块上传失败: ${manager.errorMessage}');
        return ApiResponse.error(manager.errorMessage ?? '分块上传失败');
      }
    } catch (e, stack) {
      logError('[TencentCOS] 分块上传异常: $e', stack);
      return ApiResponse.error(e.toString());
    }
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

    // 使用 xml 包解析错误响应
    try {
      final dataStr = errorData.toString();
      final document = XmlDocument.parse(dataStr);
      final errorElement = document.findElements('Error').first;

      final code = errorElement.findElements('Code').first.innerText;
      final message = errorElement.findElements('Message').first.innerText;
      final resource = errorElement.findElements('Resource').first.innerText;
      final requestId = errorElement.findElements('RequestId').first.innerText;

      // 尝试解析更多诊断信息
      String? stringToSign;
      String? formatString;
      try {
        stringToSign = errorElement.findElements('StringToSign').first.innerText;
      } catch (_) {}
      try {
        formatString = errorElement.findElements('FormatString').first.innerText;
      } catch (_) {}

      final sb = StringBuffer();
      sb.writeln('腾讯云API错误 (HTTP $statusCode)');
      sb.writeln('  Code: $code');
      sb.writeln('  Message: $message');
      if (resource.isNotEmpty) sb.writeln('  Resource: $resource');
      if (requestId.isNotEmpty) sb.writeln('  RequestId: $requestId');

      // 添加诊断信息（对签名问题特别有用）
      if (stringToSign != null && stringToSign.isNotEmpty) {
        sb.writeln('  StringToSign: $stringToSign');
      }
      if (formatString != null && formatString.isNotEmpty) {
        sb.writeln('  FormatString: $formatString');
      }

      return sb.toString();
    } catch (parseError) {
      // 如果 XML 解析失败，回退到原始方式
      return 'HTTP $statusCode error: $errorData';
    }
  }
}
