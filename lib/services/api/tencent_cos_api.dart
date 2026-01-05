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
import 'tencent/tencent_multipart_download_manager.dart';
import 'tencent/tencent_signature_generator.dart';

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

  /// 签名生成器实例（延迟初始化）
  TencentSignatureGenerator? _signatureGenerator;

  /// 获取签名生成器
  TencentSignatureGenerator _getSignatureGenerator() {
    _signatureGenerator ??= TencentSignatureGenerator(
      credential: credential,
      debugMode: _debugSignature,
    );
    return _signatureGenerator!;
  }

  /// 生成腾讯云COS签名
  String _getSignature(
    String method,
    String path,
    Map<String, String> headers, {
    Map<String, String>? queryParams,
  }) {
    return _getSignatureGenerator().generate(
      method: method,
      path: path,
      headers: headers,
      queryParams: queryParams,
    );
  }

  /// URL 编码（用于 queryParams 编码，圆括号等特殊字符也需要编码）
  String _urlEncode(String value) {
    return Uri.encodeComponent(value);
  }

  /// marker 值的特殊编码：encodeComponent 基础上额外编码圆括号
  String _encodeMarkerValue(String value) {
    String encoded = Uri.encodeComponent(value);
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
        final result = _parseObjectsFromXml(responseData, prefix: prefix);
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

  ListObjectsResult _parseObjectsFromXml(String xml, {String prefix = ''}) {
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

      // 过滤掉当前目录本身（避免无限递归）
      if (key == prefix) {
        continue;
      }

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

    // 解析 CommonPrefixes（文件夹/前缀）
    // 当使用 delimiter=/ 时，文件夹会出现在 CommonPrefixes 中
    final commonPrefixesElements = resultElement.findElements('CommonPrefixes');
    for (final prefixElem in commonPrefixesElements) {
      final key = prefixElem.findElements('Prefix').first.innerText;

      // 过滤掉当前目录本身（避免无限递归）
      if (key == prefix) {
        continue;
      }

      // 从 key 中提取文件夹名称（去掉末尾的 /）
      final name = key.endsWith('/')
          ? key.substring(0, key.length - 1).split('/').where((e) => e.isNotEmpty).lastOrNull ?? key
          : key.split('/').where((e) => e.isNotEmpty).lastOrNull ?? key;

      objects.add(
        ObjectFile(
          key: key,
          name: name,
          size: 0,
          lastModified: null,
          etag: '',
          type: ObjectType.folder,
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
  Future<ApiResponse<void>> downloadObject({
    required String bucketName,
    required String region,
    required String objectKey,
    required File outputFile,
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
      );

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=date;host&q-url-param-list=&q-signature=$signature',
        'Host': host,
        'Date': date,
      };

      // 使用流式响应，逐步写入文件
      final response = await _dio.get(
        url,
        options: Options(headers: headers, responseType: ResponseType.stream),
        onReceiveProgress: onProgress,
      );

      if (response.statusCode == 200) {
        // 从 ResponseBody 流式写入文件
        final responseBody = response.data as ResponseBody;
        final fileSink = outputFile.openWrite();
        await responseBody.stream.cast<List<int>>().pipe(fileSink);
        return ApiResponse.success(null);
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
  Future<ApiResponse<void>> downloadObjectMultipart({
    required String bucketName,
    required String region,
    required String objectKey,
    required File outputFile,
    int chunkSize = kDefaultChunkSize,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      log('[TencentCOS] 开始分块下载: $objectKey -> ${outputFile.path}');

      final manager = TencentMultipartDownloadManager(
        credential: credential,
        dio: _dio,
        bucketName: bucketName,
        region: region,
        objectKey: objectKey,
        chunkSize: chunkSize,
      );

      // 设置签名回调
      manager.getSignature = (method, path, {queryParams}) async {
        final date = HttpDate.format(DateTime.now().toUtc());
        final headersForSign = {
          'host': '$bucketName.cos.$region.myqcloud.com'.toLowerCase(),
          'date': date,
        };
        return _getSignature(
          method,
          path,
          headersForSign,
          queryParams: queryParams,
        );
      };

      // 下载文件
      final success = await manager.downloadFile(
        outputFile,
        onProgress: (bytesDownloaded, totalBytes) {
          onProgress?.call(bytesDownloaded, totalBytes);
        },
      );

      if (success) {
        log('[TencentCOS] 分块下载成功');
        return ApiResponse.success(null);
      } else {
        logError('[TencentCOS] 分块下载失败: ${manager.errorMessage}');
        return ApiResponse.error(manager.errorMessage ?? '分块下载失败');
      }
    } catch (e, stack) {
      logError('[TencentCOS] 分块下载异常: $e', stack);
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
    if (objectKeys.isEmpty) {
      return ApiResponse.success(null);
    }

    try {
      final host = '$bucketName.cos.$region.myqcloud.com';
      final url = 'https://$host/?delete';
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      // 构建批量删除的XML请求体
      final xmlBody = StringBuffer();
      xmlBody.write('<?xml version="1.0" encoding="UTF-8"?>');
      xmlBody.write('<Delete>');
      xmlBody.write('<Quiet>true</Quiet>');
      for (final key in objectKeys) {
        xmlBody.write('<Object><Key>${_escapeXml(key)}</Key></Object>');
      }
      xmlBody.write('</Delete>');

      final xmlBodyStr = xmlBody.toString();
      // 计算Content-MD5（Base64编码的MD5哈希原始字节）
      final md5Digest = md5.convert(utf8.encode(xmlBodyStr));
      final contentMd5 = base64Encode(md5Digest.bytes);

      // 生成签名时需要包含 Host 和 Date 头部
      // queryParams 用于签名的 CanonicalRequest HttpParameters
      final queryParams = {'delete': ''};
      final headersForSign = {'host': host, 'date': date};
      final signature = _getSignature(
        'POST',
        '/',
        headersForSign,
        queryParams: queryParams,
      );

      // 生成 urlParamList（按字典序排序，只包含参数名，不包含值）
      final sortedParamKeys = queryParams.keys.map((k) => _urlEncode(k)).toList()..sort();
      final urlParamList = sortedParamKeys.join(';');

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=date;host&q-url-param-list=$urlParamList&q-signature=$signature',
        'Content-Type': 'application/xml',
        'Content-MD5': contentMd5,
        'Host': host,
        'Date': date,
      };

      log('[TencentCOS] 批量删除对象，数量: ${objectKeys.length}');
      final response = await _dio.post(
        url,
        data: xmlBodyStr,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        log('[TencentCOS] 批量删除成功');
        return ApiResponse.success(null);
      } else {
        final errorData = response.data?.toString() ?? '';
        logError('[TencentCOS] 批量删除失败: ${response.statusCode}, 响应: $errorData');
        return ApiResponse.error(
          'Failed to delete objects',
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

  /// XML特殊字符转义
  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
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
  Future<ApiResponse<void>> renameObject({
    required String bucketName,
    required String region,
    required String sourceKey,
    required String newName,
    String prefix = '',
  }) async {
    log('[TencentCOS] 开始重命名: $sourceKey -> $newName');

    // 构建目标key
    // 如果原对象是文件夹（以/结尾），新名称也需要加/
    final isFolder = sourceKey.endsWith('/');
    final targetKey = prefix.isEmpty
        ? (isFolder ? '$newName/' : newName)
        : '$prefix$newName${isFolder ? '/' : ''}';

    // 如果源和目标相同，直接返回成功
    if (sourceKey == targetKey) {
      log('[TencentCOS] 源和目标相同，无需操作');
      return ApiResponse.success(null);
    }

    // 1. 复制对象（对于文件夹需要递归复制内部所有文件）
    if (isFolder) {
      final copyResult = await _copyFolder(
        bucketName: bucketName,
        region: region,
        sourceFolderKey: sourceKey,
        targetFolderKey: targetKey,
      );
      if (!copyResult.success) {
        return copyResult;
      }
    } else {
      final copyResult = await _copyObject(
        bucketName: bucketName,
        region: region,
        sourceKey: sourceKey,
        targetKey: targetKey,
      );
      if (!copyResult.success) {
        logError('[TencentCOS] 复制对象失败: ${copyResult.errorMessage}');
        return ApiResponse.error(copyResult.errorMessage ?? '复制对象失败');
      }
    }

    // 2. 删除源对象（对于文件夹需要递归删除内部所有对象）
    if (isFolder) {
      final deleteResult = await deleteFolder(
        bucketName: bucketName,
        region: region,
        folderKey: sourceKey,
      );
      if (!deleteResult.success) {
        logError('[TencentCOS] 删除源文件夹失败: ${deleteResult.errorMessage}');
        return ApiResponse.error('重命名成功，但删除原文件夹失败: ${deleteResult.errorMessage}');
      }
    } else {
      final deleteResult = await deleteObject(
        bucketName: bucketName,
        region: region,
        objectKey: sourceKey,
      );
      if (!deleteResult.success) {
        logError('[TencentCOS] 删除源对象失败: ${deleteResult.errorMessage}');
        return ApiResponse.error('重命名成功，但删除原对象失败: ${deleteResult.errorMessage}');
      }
    }

    log('[TencentCOS] 重命名成功: $sourceKey -> $targetKey');
    return ApiResponse.success(null);
  }

  /// 递归复制文件夹及其所有内容
  Future<ApiResponse<void>> _copyFolder({
    required String bucketName,
    required String region,
    required String sourceFolderKey,
    required String targetFolderKey,
  }) async {
    log('[TencentCOS] 开始递归复制文件夹: $sourceFolderKey -> $targetFolderKey');

    // 确保源和目标路径都以 / 结尾
    final normalizedSourceKey = sourceFolderKey.endsWith('/') ? sourceFolderKey : '$sourceFolderKey/';
    final normalizedTargetKey = targetFolderKey.endsWith('/') ? targetFolderKey : '$targetFolderKey/';

    // 首先复制文件夹标记
    final folderMarkerCopy = await _copyObject(
      bucketName: bucketName,
      region: region,
      sourceKey: normalizedSourceKey,
      targetKey: normalizedTargetKey,
    );

    if (!folderMarkerCopy.success) {
      logError('[TencentCOS] 复制文件夹标记失败: ${folderMarkerCopy.errorMessage}');
      return folderMarkerCopy;
    }

    // 递归列出源文件夹内的所有对象并复制
    String? marker;
    int successCount = 0;
    int failCount = 0;

    while (true) {
      final listResult = await listObjects(
        bucketName: bucketName,
        region: region,
        prefix: normalizedSourceKey,
        delimiter: '', // 不使用delimiter，获取所有对象
        maxKeys: 1000,
        marker: marker,
      );

      if (!listResult.success || listResult.data == null) {
        logError('[TencentCOS] 列出文件夹内容失败: ${listResult.errorMessage}');
        return ApiResponse.error('列出文件夹内容失败: ${listResult.errorMessage}');
      }

      final objects = listResult.data!.objects;

      // 排除文件夹标记本身
      final fileObjects = objects.where((obj) => obj.key != normalizedSourceKey).toList();

      // 复制每个文件
      for (final obj in fileObjects) {
        // 计算相对路径：从源文件夹前缀之后的部分
        final relativePath = obj.key.substring(normalizedSourceKey.length);
        final targetKey = '$normalizedTargetKey$relativePath';

        log('[TencentCOS] 复制文件: ${obj.key} -> $targetKey');
        final copyResult = await _copyObject(
          bucketName: bucketName,
          region: region,
          sourceKey: obj.key,
          targetKey: targetKey,
        );

        if (copyResult.success) {
          successCount++;
        } else {
          failCount++;
          logError('[TencentCOS] 复制文件失败: ${obj.key}, ${copyResult.errorMessage}');
        }
      }

      // 检查是否还有更多对象
      if (listResult.data!.isTruncated) {
        marker = listResult.data!.nextMarker;
      } else {
        break;
      }
    }

    log('[TencentCOS] 文件夹复制完成: $successCount 个成功, $failCount 个失败');
    if (failCount > 0) {
      return ApiResponse.error('部分文件复制失败: $failCount 个');
    }
    return ApiResponse.success(null);
  }

  @override
  Future<ApiResponse<void>> deleteFolder({
    required String bucketName,
    required String region,
    required String folderKey,
  }) async {
    log('[TencentCOS] 开始删除文件夹: $folderKey');

    // 获取文件夹内的所有对象（不使用delimiter，递归列出所有对象）
    String? marker;
    int totalFailed = 0;

    while (true) {
      final listResult = await listObjects(
        bucketName: bucketName,
        region: region,
        prefix: folderKey,
        delimiter: '', // 不使用delimiter，获取所有对象
        maxKeys: 1000,
        marker: marker,
      );

      if (!listResult.success || listResult.data == null) {
        logError('[TencentCOS] 列出文件夹内容失败: ${listResult.errorMessage}');
        return ApiResponse.error('列出文件夹内容失败: ${listResult.errorMessage}');
      }

      final objects = listResult.data!.objects;

      // 收集除文件夹标记外的所有对象key
      final objectKeys = objects
          .where((obj) => obj.key != folderKey)
          .map((obj) => obj.key)
          .toList();

      // 批量删除对象
      if (objectKeys.isNotEmpty) {
        log('[TencentCOS] 批量删除 ${objectKeys.length} 个对象');
        final deleteResult = await deleteObjects(
          bucketName: bucketName,
          region: region,
          objectKeys: objectKeys,
        );

        if (deleteResult.success) {
          log('[TencentCOS] 批量删除完成: ${objectKeys.length} 个对象');
        } else {
          totalFailed += objectKeys.length;
          logError('[TencentCOS] 批量删除失败: ${deleteResult.errorMessage}');
        }
      }

      // 检查是否还有更多对象
      if (listResult.data!.isTruncated) {
        marker = listResult.data!.nextMarker;
      } else {
        break;
      }
    }

    // 最后删除文件夹标记对象
    log('[TencentCOS] 删除文件夹标记: $folderKey');
    final result = await deleteObject(
      bucketName: bucketName,
      region: region,
      objectKey: folderKey,
    );

    if (result.success) {
      log('[TencentCOS] 文件夹删除成功: $folderKey${totalFailed > 0 ? '，$totalFailed 个失败' : ''}');
      return ApiResponse.success(null);
    } else {
      logError('[TencentCOS] 删除文件夹标记失败: ${result.errorMessage}');
      return ApiResponse.error('删除文件夹标记失败: ${result.errorMessage}');
    }
  }

  @override
  Future<ApiResponse<void>> copyObject({
    required String bucketName,
    required String region,
    required String sourceKey,
    required String targetKey,
  }) {
    return _copyObject(
      bucketName: bucketName,
      region: region,
      sourceKey: sourceKey,
      targetKey: targetKey,
    );
  }

  @override
  Future<ApiResponse<void>> copyFolder({
    required String bucketName,
    required String region,
    required String sourceFolderKey,
    required String targetFolderKey,
  }) {
    return _copyFolder(
      bucketName: bucketName,
      region: region,
      sourceFolderKey: sourceFolderKey,
      targetFolderKey: targetFolderKey,
    );
  }

  /// 复制对象（内部方法）
  Future<ApiResponse<void>> _copyObject({
    required String bucketName,
    required String region,
    required String sourceKey,
    required String targetKey,
  }) async {
    try {
      final host = '$bucketName.cos.$region.myqcloud.com';
      final url = 'https://$host/$targetKey';
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;
      final keyTime = '$now;$end';

      // 生成 GMT 格式的 Date 头部
      final date = HttpDate.format(DateTime.now().toUtc());

      // 生成签名时需要包含 Host 和 Date 头部
      final headersForSign = {'host': host, 'date': date};
      final signature = _getSignature(
        'PUT',
        '/$targetKey',
        headersForSign,
      );

      // 源对象需要 URL 编码
      final encodedSourceKey = Uri.encodeComponent(sourceKey);

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=date;host&q-url-param-list=&q-signature=$signature',
        'Content-Type': 'application/octet-stream',
        'Host': host,
        'Date': date,
        'x-cos-copy-source': '/$bucketName/$encodedSourceKey',
      };

      log('[TencentCOS] 复制对象: $sourceKey -> $targetKey');
      final response = await _dio.put(
        url,
        data: <int>[],
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        log('[TencentCOS] 复制对象成功');
        return ApiResponse.success(null);
      } else {
        final errorData = response.data?.toString() ?? '';
        logError('[TencentCOS] 复制对象失败: ${response.statusCode}, 响应: $errorData');
        return ApiResponse.error(
          'Failed to copy object',
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
    dynamic errorData = response.data;

    if (errorData == null) {
      return 'HTTP $statusCode error: ${e.message}';
    }

    // 处理字节数组格式的错误响应（腾讯云返回二进制XML）
    String dataStr;
    if (errorData is List<int>) {
      // 将字节数组解码为UTF-8字符串
      dataStr = utf8.decode(errorData);
    } else {
      dataStr = errorData.toString();
    }

    // 使用 xml 包解析错误响应
    try {
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
      return 'HTTP $statusCode error: $dataStr';
    }
  }
}
