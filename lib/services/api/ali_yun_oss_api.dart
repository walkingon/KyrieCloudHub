import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../../models/bucket.dart';
import '../../models/object_file.dart';
import '../../models/platform_credential.dart';
import '../../utils/logger.dart';
import 'cloud_platform_api.dart';
import '../multipart_upload/file_chunk_reader.dart';
import 'aliyun/aliyun_signature_generator.dart';

/// 阿里云OSS API实现
///
/// 阿里云OSS V4签名算法说明：
/// 1. 使用 ISO8601 格式的日期时间 (如: 20250417T111832Z)
/// 2. Credential = AccessKeyId/YYYYMMDD/region/oss/aliyun_v4_request
/// 3. AdditionalHeaders = 参与签名的HTTP头部列表（按小写字母排序，分号分隔）
/// 4. 使用 HMAC-SHA256 计算签名
class AliyunOssApi implements ICloudPlatformApi {
  /// 控制签名生成过程日志的打印开关
  static const bool _debugSignature = false;

  final PlatformCredential credential;
  late final Dio _dio;

  AliyunOssApi(this.credential) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
  }

  /// 签名生成器实例（延迟初始化）
  AliyunSignatureGenerator? _signatureGenerator;

  /// 获取签名生成器
  AliyunSignatureGenerator _getSignatureGenerator() {
    _signatureGenerator ??= AliyunSignatureGenerator(
      credential: credential,
      region: credential.region,
      debugMode: _debugSignature,
    );
    return _signatureGenerator!;
  }

  /// 生成阿里云OSS V4签名
  String _getSignatureV4({
    required String method,
    String? bucketName,
    String? objectKey,
    required Map<String, String> headers,
    Map<String, String>? queryParams,
  }) {
    return _getSignatureGenerator().generate(
      method: method,
      bucketName: bucketName,
      objectKey: objectKey,
      headers: headers,
      queryParams: queryParams,
    );
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
  /// 注意：Uri.encodeComponent 不会编码圆括号，需要额外处理
  String _encodePath(String path) {
    // 使用 Uri.encodeComponent 编码，然后还原 /
    // 注意：Uri.encodeComponent 不会编码圆括号 ()，需要手动编码
    return Uri.encodeComponent(path)
        .replaceAll('%2F', '/')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29');
  }

  /// marker 值的特殊编码：encodeComponent 基础上额外编码圆括号
  /// 解决文件名包含圆括号时的签名不匹配问题
  String _encodeMarkerValue(String value) {
    // 先用 encodeComponent 编码基础字符
    String encoded = Uri.encodeComponent(value);
    // 额外编码圆括号 ( -> %28, ) -> %29
    encoded = encoded.replaceAll('(', '%28').replaceAll(')', '%29');
    return encoded;
  }

  /// 生成分块ETag（用于备用方案）
  String _generatePartETag(Uint8List data) {
    final hash = md5.convert(data);
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
      final response = await _dio.get(url, options: Options(headers: headers));
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
      // marker 值使用 _encodeMarkerValue 预先编码（解决圆括号等特殊字符签名不匹配问题）
      // 注意：URL 构建时只编码 key，value 使用已编码的值，避免双重编码
      final queryParams = <String, String>{
        'prefix': prefix,
        'delimiter': delimiter,
        'max-keys': maxKeys.toString(),
      };
      if (marker != null && marker.isNotEmpty) {
        queryParams['marker'] = _encodeMarkerValue(marker);
      }

      // 构建 URL 时只编码 key，value 已经是编码后的值
      final queryString = queryParams.entries
          .map(
            (e) => '${Uri.encodeComponent(e.key)}=${e.value}',
          )
          .join('&');
      final url = 'https://$host/?$queryString';

      log('[AliyunOSS] 开始查询对象列表, URL: $url');

      // 签名时也使用编码后的 queryParams（确保签名与实际请求一致）
      final signedQueryParams = <String, String>{
        'prefix': prefix,
        'delimiter': delimiter,
        'max-keys': maxKeys.toString(),
      };
      if (marker != null && marker.isNotEmpty) {
        signedQueryParams['marker'] = _encodeMarkerValue(marker);
      }

      final headers = _buildHeaders(
        method: 'GET',
        bucketName: bucketName,
        queryParams: signedQueryParams,
      );

      log('[AliyunOSS] 发送GET请求...');
      final response = await _dio.get(url, options: Options(headers: headers));

      log('[AliyunOSS] 响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = response.data?.toString() ?? '';
        final result = _parseObjectsFromXml(responseData, prefix: prefix);
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

  ListObjectsResult _parseObjectsFromXml(String xml, {String prefix = ''}) {
    final objects = <ObjectFile>[];
    bool isTruncated = false;
    String? nextMarker;

    try {
      final document = XmlDocument.parse(xml);
      final resultElement = document.findElements('ListBucketResult').first;

      // 解析分页信息
      try {
        final isTruncatedElement = resultElement.findElements('IsTruncated').first;
        isTruncated = isTruncatedElement.innerText.toLowerCase() == 'true';
        log('[AliyunOSS] IsTruncated: $isTruncated');
      } catch (e) {
        isTruncated = false;
      }

      try {
        final nextMarkerElement = resultElement.findElements('NextMarker').first;
        nextMarker = nextMarkerElement.innerText;
        log('[AliyunOSS] NextMarker: $nextMarker');
      } catch (e) {
        nextMarker = null;
      }

      // 解析文件内容
      final contentsElements = resultElement.findElements('Contents');

      for (final content in contentsElements) {
        final key = content.findElements('Key').first.innerText;

        // 过滤掉当前目录本身（避免无限递归）
        // 如果 key 等于当前 prefix，说明是当前目录的"自引用"，需要过滤掉
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
            etag: etag.replaceAll('"', ''),
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
        // 如果 key 等于当前 prefix，说明是当前目录的"自引用"，需要过滤掉
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
    } catch (e) {
      logError('[AliyunOSS] 解析对象XML失败: $e');
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
      final host = _getEndpoint(bucketName);
      final url = 'https://$host/${_encodePath(objectKey)}';

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
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD', // 阿里云V4签名要求
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

      final response = await _dio.put(
        url,
        data: data,
        options: Options(headers: headers),
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
  Future<ApiResponse<void>> downloadObject({
    required String bucketName,
    required String region,
    required String objectKey,
    required File outputFile,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final host = _getEndpoint(bucketName);
      final url = 'https://$host/${_encodePath(objectKey)}';

      log('[AliyunOSS] 开始下载对象: $objectKey');

      final headers = _buildHeaders(
        method: 'GET',
        bucketName: bucketName,
        objectKey: objectKey,
      );

      // 使用流式响应，逐步写入文件
      final response = await _dio.get(
        url,
        options: Options(headers: headers, responseType: ResponseType.stream),
        onReceiveProgress: onProgress,
      );

      if (response.statusCode == 200) {
        final stream = response.data as Stream<List<int>>;
        final fileSink = outputFile.openWrite();
        await stream.pipe(fileSink);
        log('[AliyunOSS] 下载成功');
        return ApiResponse.success(null);
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
  Future<ApiResponse<void>> downloadObjectMultipart({
    required String bucketName,
    required String region,
    required String objectKey,
    required File outputFile,
    int chunkSize = kDefaultChunkSize,
    int concurrency = kDefaultConcurrency,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      log('[AliyunOSS] 开始分块下载: $objectKey -> ${outputFile.path}');

      final host = _getEndpoint(bucketName);
      final url = 'https://$host/${_encodePath(objectKey)}';

      // 1. 获取文件大小 (HEAD请求)
      final headHeaders = _buildHeaders(
        method: 'HEAD',
        bucketName: bucketName,
        objectKey: objectKey,
      );

      final headResponse = await _dio.head(url, options: Options(headers: headHeaders));
      if (headResponse.statusCode != 200) {
        return ApiResponse.error('Failed to get file size', statusCode: headResponse.statusCode);
      }

      final contentLength = headResponse.headers['content-length'];
      if (contentLength == null || contentLength.isEmpty) {
        return ApiResponse.error('Content-Length header not found');
      }
      final totalBytes = int.parse(contentLength.first);
      log('[AliyunOSS] 文件总大小: $totalBytes bytes');

      // 2. 计算分块范围
      final chunks = <Map<String, dynamic>>[];
      final totalChunks = (totalBytes / chunkSize).ceil();
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = min<int>(start + chunkSize - 1, totalBytes - 1);
        chunks.add({
          'partNumber': i + 1,
          'start': start,
          'end': end,
          'size': end - start + 1,
          'data': null,
        });
      }
      log('[AliyunOSS] 分块数: ${chunks.length}');

      // 3. 并发下载分块
      int downloadedBytes = 0;
      final failedChunks = <Map<String, dynamic>>[];

      for (int i = 0; i < chunks.length; i += concurrency) {
        final batch = chunks.sublist(i, min<int>(i + concurrency, chunks.length));

        // 并发下载这一批分块
        final results = await Future.wait(
          batch.map((chunk) async {
            try {
              final rangeHeaders = _buildHeaders(
                method: 'GET',
                bucketName: bucketName,
                objectKey: objectKey,
                extraHeaders: {
                  'Range': 'bytes=${chunk['start']}-${chunk['end']}',
                },
              );

              final response = await _dio.get(
                url,
                options: Options(headers: rangeHeaders, responseType: ResponseType.bytes),
              );

              if (response.statusCode == 206) {
                chunk['data'] = Uint8List.fromList(response.data as List<int>);
                downloadedBytes += (chunk['size'] as int);
                onProgress?.call(downloadedBytes, totalBytes);
                return true;
              }
              return false;
            } catch (e) {
              logError('[AliyunOSS] 分块下载失败: $e');
              return false;
            }
          }),
        );

        // 记录失败的分块
        for (int j = 0; j < results.length; j++) {
          if (!results[j]) {
            failedChunks.add(batch[j]);
          }
        }
      }

      // 重试失败的分块
      if (failedChunks.isNotEmpty) {
        log('[AliyunOSS] 重试 ${failedChunks.length} 个失败分块...');
        for (final chunk in failedChunks) {
          try {
            final rangeHeaders = _buildHeaders(
              method: 'GET',
              bucketName: bucketName,
              objectKey: objectKey,
              extraHeaders: {
                'Range': 'bytes=${chunk['start']}-${chunk['end']}',
              },
            );

            final response = await _dio.get(
              url,
              options: Options(headers: rangeHeaders, responseType: ResponseType.bytes),
            );

            if (response.statusCode == 206) {
              chunk['data'] = Uint8List.fromList(response.data as List<int>);
            } else {
              return ApiResponse.error('Failed to download chunk');
            }
          } catch (e) {
            return ApiResponse.error('Failed to retry chunk: $e');
          }
        }
      }

      // 4. 合并分块到文件
      log('[AliyunOSS] 开始合并分块...');
      final raf = await outputFile.open(mode: FileMode.writeOnly);
      try {
        for (final chunk in chunks) {
          if (chunk['data'] != null) {
            await raf.writeFrom(chunk['data'] as Uint8List);
            chunk['data'] = null; // 释放内存
          }
        }
      } finally {
        await raf.close();
      }

      log('[AliyunOSS] 分块下载成功');
      return ApiResponse.success(null);
    } on DioException catch (e) {
      final errorDetail = _parseAliyunError(e);
      logError('[AliyunOSS] DioException: $errorDetail');
      return ApiResponse.error(errorDetail, statusCode: e.response?.statusCode);
    } catch (e, stack) {
      logError('[AliyunOSS] 分块下载异常: $e', stack);
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
      final url = 'https://$host/${_encodePath(objectKey)}';

      log('[AliyunOSS] 开始删除对象: $objectKey');

      final headers = _buildHeaders(
        method: 'DELETE',
        bucketName: bucketName,
        objectKey: objectKey,
      );

      final response = await _dio.delete(url, options: Options(headers: headers));

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
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD', // 阿里云V4签名要求
        'host': _getEndpoint(bucketName),
      };

      // 生成签名
      final signature = _getSignatureV4(
        method: 'POST',
        bucketName: bucketName,
        objectKey: '',  // 空字符串，path为 /
        queryParams: {'delete': ''},  // ?delete 作为查询参数
        headers: headers,
      );
      headers['Authorization'] = signature;

      final response = await _dio.post(
        url,
        data: requestBodyBytes,
        options: Options(headers: headers),
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
  Future<ApiResponse<void>> createFolder({
    required String bucketName,
    required String region,
    required String folderName,
    String prefix = '',
  }) async {
    try {
      // 构建文件夹的key：prefix + folderName + /
      final objectKey = prefix.isEmpty ? '$folderName/' : '$prefix$folderName/';
      final host = _getEndpoint(bucketName);
      final url = 'https://$host/${_encodePath(objectKey)}';

      log('[AliyunOSS] 创建文件夹: $objectKey');

      // 生成 GMT 格式的 Date 头部和 ISO8601 格式的 x-oss-date
      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final headers = {
        'Authorization': '',
        'Content-Type': 'application/directory',
        'date': httpDate,
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD', // 阿里云V4签名要求
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

      final response = await _dio.put(
        url,
        data: <int>[],
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        log('[AliyunOSS] 文件夹创建成功: $objectKey');
        return ApiResponse.success(null);
      } else {
        logError('[AliyunOSS] 创建文件夹失败: ${response.statusCode}');
        return ApiResponse.error(
          'Failed to create folder',
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

  @override
  Future<ApiResponse<void>> renameObject({
    required String bucketName,
    required String region,
    required String sourceKey,
    required String newName,
    String prefix = '',
  }) async {
    log('[AliyunOSS] 开始重命名: $sourceKey -> $newName');

    // 构建目标key
    // 如果原对象是文件夹（以/结尾），新名称也需要加/
    final isFolder = sourceKey.endsWith('/');
    final targetKey = prefix.isEmpty
        ? (isFolder ? '$newName/' : newName)
        : '$prefix$newName${isFolder ? '/' : ''}';

    // 如果源和目标相同，直接返回成功
    if (sourceKey == targetKey) {
      log('[AliyunOSS] 源和目标相同，无需操作');
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
        logError('[AliyunOSS] 复制对象失败: ${copyResult.errorMessage}');
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
        logError('[AliyunOSS] 删除源文件夹失败: ${deleteResult.errorMessage}');
        return ApiResponse.error('重命名成功，但删除原文件夹失败: ${deleteResult.errorMessage}');
      }
    } else {
      final deleteResult = await deleteObject(
        bucketName: bucketName,
        region: region,
        objectKey: sourceKey,
      );
      if (!deleteResult.success) {
        logError('[AliyunOSS] 删除源对象失败: ${deleteResult.errorMessage}');
        return ApiResponse.error('重命名成功，但删除原对象失败: ${deleteResult.errorMessage}');
      }
    }

    log('[AliyunOSS] 重命名成功: $sourceKey -> $targetKey');
    return ApiResponse.success(null);
  }

  /// 递归复制文件夹及其所有内容
  Future<ApiResponse<void>> _copyFolder({
    required String bucketName,
    required String region,
    required String sourceFolderKey,
    required String targetFolderKey,
  }) async {
    log('[AliyunOSS] 开始递归复制文件夹: $sourceFolderKey -> $targetFolderKey');

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
      logError('[AliyunOSS] 复制文件夹标记失败: ${folderMarkerCopy.errorMessage}');
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
        logError('[AliyunOSS] 列出文件夹内容失败: ${listResult.errorMessage}');
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

        log('[AliyunOSS] 复制文件: ${obj.key} -> $targetKey');
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
          logError('[AliyunOSS] 复制文件失败: ${obj.key}, ${copyResult.errorMessage}');
        }
      }

      // 检查是否还有更多对象
      if (listResult.data!.isTruncated) {
        marker = listResult.data!.nextMarker;
      } else {
        break;
      }
    }

    log('[AliyunOSS] 文件夹复制完成: $successCount 个成功, $failCount 个失败');
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
    log('[AliyunOSS] 开始删除文件夹: $folderKey');

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
        logError('[AliyunOSS] 列出文件夹内容失败: ${listResult.errorMessage}');
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
        log('[AliyunOSS] 批量删除 ${objectKeys.length} 个对象');
        final deleteResult = await deleteObjects(
          bucketName: bucketName,
          region: region,
          objectKeys: objectKeys,
        );

        if (deleteResult.success) {
          log('[AliyunOSS] 批量删除完成: ${objectKeys.length} 个对象');
        } else {
          totalFailed += objectKeys.length;
          logError('[AliyunOSS] 批量删除失败: ${deleteResult.errorMessage}');
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
    log('[AliyunOSS] 删除文件夹标记: $folderKey');
    final result = await deleteObject(
      bucketName: bucketName,
      region: region,
      objectKey: folderKey,
    );

    if (result.success) {
      log('[AliyunOSS] 文件夹删除成功: $folderKey${totalFailed > 0 ? '，$totalFailed 个失败' : ''}');
      return ApiResponse.success(null);
    } else {
      logError('[AliyunOSS] 删除文件夹标记失败: ${result.errorMessage}');
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
      final host = _getEndpoint(bucketName);
      final url = 'https://$host/${_encodePath(targetKey)}';

      log('[AliyunOSS] 复制对象: $sourceKey -> $targetKey');

      // 生成 GMT 格式的 Date 头部和 ISO8601 格式的 x-oss-date
      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      // 构建源对象URI（需要编码）
      final encodedSourceKey = _encodePath(sourceKey);

      final headers = {
        'Authorization': '',
        'Content-Type': 'application/octet-stream',
        'date': httpDate,
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD', // 阿里云V4签名要求
        'host': _getEndpoint(bucketName),
        'x-oss-copy-source': '/$bucketName/$encodedSourceKey',
      };

      // 生成签名
      final signature = _getSignatureV4(
        method: 'PUT',
        bucketName: bucketName,
        objectKey: targetKey,
        headers: headers,
      );
      headers['Authorization'] = signature;

      final response = await _dio.put(
        url,
        data: <int>[],
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        log('[AliyunOSS] 复制对象成功');
        return ApiResponse.success(null);
      } else {
        final errorData = response.data?.toString() ?? '';
        logError('[AliyunOSS] 复制对象失败: ${response.statusCode}, 响应: $errorData');
        return ApiResponse.error(
          'Failed to copy object',
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
        queryParams: {'uploads': ''},
      );

      log('[AliyunOSS] 初始化分块上传...');
      final initResponse = await _dio.post(initUrl, options: Options(headers: initHeaders));

      if (initResponse.statusCode != 200) {
        return ApiResponse.error(
          'Failed to initiate multipart upload',
          statusCode: initResponse.statusCode,
        );
      }

      // 解析UploadId - Dio使用ResponseType.plain时data可能是List<int>
      String responseData;
      if (initResponse.data is List<int>) {
        responseData = utf8.decode(initResponse.data as List<int>);
      } else {
        responseData = initResponse.data?.toString() ?? '';
      }
      log('[AliyunOSS] 响应数据: $responseData');

      String? uploadId;
      try {
        final document = XmlDocument.parse(responseData);
        // 使用 findAllElements 递归查找所有匹配的元素
        final uploadIdElements = document.findAllElements('UploadId');
        if (uploadIdElements.isNotEmpty) {
          uploadId = uploadIdElements.first.innerText;
        } else {
          // 备选方案：尝试从根元素开始查找
          final root = document.rootElement;
          uploadId = root.getElement('UploadId')?.innerText;
        }
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

          final uploadResponse = await _dio.put(
            uploadUrl,
            data: chunk.data,
            options: Options(headers: uploadHeaders),
          );

          // 直接打印响应状态（绕过可能的日志拦截问题）
          final statusCode = uploadResponse.statusCode ?? 0;
          final etagHeader = uploadResponse.headers['etag']?.first ?? 'NOT_FOUND';
          log('[AliyunOSS] 分块 $partNumber 响应: status=$statusCode, etag=$etagHeader');

          if (statusCode == 200) {
            // 记录已上传的分块信息
            final etagHeaders = uploadResponse.headers['etag'];
            final etag = etagHeaders != null && etagHeaders.isNotEmpty
                ? etagHeaders.first.replaceAll('"', '')
                : '';
            uploadedParts.add({
              'PartNumber': partNumber,
              'ETag': etag.isNotEmpty ? etag : _generatePartETag(chunk.data),
            });

            onProgress?.call(chunk.offset + chunk.size, fileSize);
            log('[AliyunOSS] 分块 $partNumber 上传成功, ETag: ${uploadedParts.last['ETag']}');
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
        queryParams: {'uploadId': uploadId!},
      );

      final completeResponse = await _dio.post(
        completeUrl,
        data: completeBodyBytes,
        options: Options(headers: completeHeaders),
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
