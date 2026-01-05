import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../../models/platform_credential.dart';
import '../../../services/api/cloud_platform_api.dart';
import '../../../utils/logger.dart';
import '../../../utils/file_chunk_reader.dart';

/// 已上传分块信息
class AliyunUploadedPart {
  final int partNumber;
  final String eTag;
  final int size;

  AliyunUploadedPart({
    required this.partNumber,
    required this.eTag,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
        'partNumber': partNumber,
        'eTag': eTag,
        'size': size,
      };
}

/// 分块上传状态
enum AliyunMultipartUploadStatus {
  idle,
  initiating,
  uploading,
  completing,
  completed,
  failed,
  cancelled,
}

/// 阿里云OSS分片上传管理器
///
/// 负责管理整个分块上传流程：
/// 1. 初始化分块上传 (Initiate Multipart Upload)
/// 2. 上传分块 (Upload Part)
/// 3. 完成分块上传 (Complete Multipart Upload)
/// 4. 取消分块上传 (Abort Multipart Upload)
class AliyunMultipartUploadManager {
  final PlatformCredential credential;
  final Dio dio;
  final String bucketName;
  final String region;
  final String objectKey;
  final int chunkSize;

  /// 上传任务ID
  String? uploadId;

  /// 已上传的分块信息
  final Map<int, AliyunUploadedPart> uploadedParts = {};

  /// 当前状态
  AliyunMultipartUploadStatus status = AliyunMultipartUploadStatus.idle;

  /// 已上传的字节数
  int uploadedBytes = 0;

  /// 总文件大小
  int totalBytes = 0;

  /// 错误信息
  String? errorMessage;

  /// 进度回调
  void Function(int bytesUploaded, int totalBytes)? onProgress;

  /// 状态回调
  void Function(AliyunMultipartUploadStatus status)? onStatusChanged;

  /// 签名方法回调（由外部传入）
  Future<String> Function({
    required String method,
    String? bucketName,
    String? objectKey,
    required Map<String, String> headers,
    Map<String, String>? queryParams,
  })? getSignature;

  /// 进度更新间隔（毫秒）- 使用更长的间隔减少消息数量
  static const _progressThrottleMs = 500;

  /// 进度更新计时器（确保最多只有一个进度回调待执行）
  Timer? _progressTimer;

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

  /// 获取地域对应的endpoint后缀
  String _getRegionEndpoint() {
    final region = this.region;
    if (region.startsWith('oss-')) {
      return 'oss-${region.substring(4)}.aliyuncs.com';
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
    final normalizedRegion = mapping[region] ?? region;
    return 'oss-$normalizedRegion.aliyuncs.com';
  }

  /// 获取请求主机
  String get _host => '$bucketName.${_getRegionEndpoint()}';

  /// 对路径进行 URI 编码（不编码正斜杠）
  String _encodePath(String path) {
    return Uri.encodeComponent(path)
        .replaceAll('%2F', '/')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29');
  }

  AliyunMultipartUploadManager({
    required this.credential,
    required this.dio,
    required this.bucketName,
    required this.region,
    required this.objectKey,
    this.chunkSize = FileChunkReader.defaultChunkSize,
  });

  /// 更新状态
  void _setStatus(AliyunMultipartUploadStatus newStatus) {
    if (status != newStatus) {
      status = newStatus;
      log('[AliyunMultipartUploadManager] 状态变更: $newStatus');
      onStatusChanged?.call(newStatus);
    }
  }

  /// 生成签名（内部方法）
  Future<String> _generateSignature({
    required String method,
    String? objectKey,
    Map<String, String>? extraHeaders,
    Map<String, String>? queryParams,
  }) async {
    if (getSignature == null) {
      throw Exception('签名方法未设置，请传入 getSignature 回调');
    }

    final date = DateTime.now().toUtc();
    final iso8601DateTime = _formatIso8601DateTime(date);

    final headers = <String, String>{
      'host': _host,
      'x-oss-date': iso8601DateTime,
      'x-oss-content-sha256': 'UNSIGNED-PAYLOAD',
      ...?extraHeaders,
    };

    final signature = await getSignature!(
      method: method,
      bucketName: bucketName,
      objectKey: objectKey,
      headers: headers,
      queryParams: queryParams,
    );

    return signature;
  }

  /// 初始化分块上传
  Future<bool> initiate() async {
    try {
      _setStatus(AliyunMultipartUploadStatus.initiating);
      log('[AliyunMultipartUploadManager] 开始初始化分块上传: $objectKey');

      // 签名时需要包含 Content-Type（阿里云V4签名要求）
      final signature = await _generateSignature(
        method: 'POST',
        objectKey: objectKey,
        extraHeaders: {'Content-Type': 'application/xml'},
        queryParams: {'uploads': ''},
      );

      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final headers = {
        'Authorization': signature,
        'Content-Type': 'application/xml',
        'date': httpDate,
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD',
        'host': _host,
      };

      final url = 'https://$_host/${_encodePath(objectKey)}?uploads';
      final response = await dio.post(
        url,
        data: [],
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        // 解析XML响应获取 UploadId
        String responseData;
        if (response.data is List<int>) {
          responseData = utf8.decode(response.data as List<int>);
        } else {
          responseData = response.data?.toString() ?? '';
        }
        log('[AliyunMultipartUploadManager] 初始化响应: $responseData');

        String? parsedUploadId;
        try {
          final document = XmlDocument.parse(responseData);
          final uploadIdElements = document.findAllElements('UploadId');
          if (uploadIdElements.isNotEmpty) {
            parsedUploadId = uploadIdElements.first.innerText;
          } else {
            final root = document.rootElement;
            parsedUploadId = root.getElement('UploadId')?.innerText;
          }
        } catch (e) {
          logError('[AliyunMultipartUploadManager] 解析UploadId失败: $e');
          return false;
        }

        uploadId = parsedUploadId;
        log('[AliyunMultipartUploadManager] 初始化成功, UploadId: $uploadId');
        uploadedParts.clear();
        uploadedBytes = 0;
        return true;
      } else {
        errorMessage = '初始化分块上传失败: ${response.statusCode}';
        logError('[AliyunMultipartUploadManager] $errorMessage');
        _setStatus(AliyunMultipartUploadStatus.failed);
        return false;
      }
    } catch (e, stack) {
      errorMessage = '初始化分块上传异常: $e';
      logError('[AliyunMultipartUploadManager] $errorMessage', stack);
      _setStatus(AliyunMultipartUploadStatus.failed);
      return false;
    }
  }

  /// 上传单个分块
  Future<bool> uploadPart(int partNumber, Uint8List data) async {
    if (uploadId == null) {
      errorMessage = 'UploadId 为空，请先调用 initiate()';
      logError('[AliyunMultipartUploadManager] $errorMessage');
      return false;
    }

    try {
      // 计算 Content-MD5
      final digest = md5.convert(data);
      final md5Base64 = base64Encode(digest.bytes);

      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final signature = await _generateSignature(
        method: 'PUT',
        objectKey: objectKey,
        extraHeaders: {
          'Content-Type': 'application/octet-stream',
          'Content-MD5': md5Base64,
        },
        queryParams: {
          'partNumber': partNumber.toString(),
          'uploadId': uploadId!,
        },
      );

      final headers = {
        'Authorization': signature,
        'Content-Type': 'application/octet-stream',
        'Content-MD5': md5Base64,
        'Content-Length': data.length.toString(),
        'date': httpDate,
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD',
        'host': _host,
      };

      final url = 'https://$_host/${_encodePath(objectKey)}?partNumber=$partNumber&uploadId=$uploadId';
      final response = await dio.put(
        url,
        data: data,
        options: Options(headers: headers),
      );

      final statusCode = response.statusCode ?? 0;
      final etagHeader = response.headers['etag']?.first ?? 'NOT_FOUND';
      log('[AliyunMultipartUploadManager] 分块 $partNumber 响应: status=$statusCode, etag=$etagHeader');

      if (statusCode == 200) {
        // 获取 ETag - 从响应头中获取
        String eTag = '';
        final etagValues = response.headers['etag'];
        if (etagValues != null && etagValues.isNotEmpty) {
          eTag = etagValues.first.replaceAll('"', '');
        }

        if (eTag.isNotEmpty) {
          uploadedParts[partNumber] = AliyunUploadedPart(
            partNumber: partNumber,
            eTag: eTag,
            size: data.length,
          );
        } else {
          // 备用方案：使用 MD5 作为 ETag
          uploadedParts[partNumber] = AliyunUploadedPart(
            partNumber: partNumber,
            eTag: digest.toString(),
            size: data.length,
          );
        }

        // 线程安全地更新进度
        _updateProgress(data.length);

        log('[AliyunMultipartUploadManager] 分块 $partNumber 上传成功, ETag: ${uploadedParts[partNumber]?.eTag}');
        return true;
      } else {
        logError('[AliyunMultipartUploadManager] 分块 $partNumber 上传失败: $statusCode');
        return false;
      }
    } catch (e, stack) {
      logError('[AliyunMultipartUploadManager] 分块 $partNumber 上传异常: $e', stack);
      return false;
    }
  }

  /// 线程安全的进度更新（带节流）
  void _updateProgress(int bytesJustUploaded) {
    uploadedBytes += bytesJustUploaded;
    _scheduleProgressUpdate();
  }

  /// 安排进度更新（使用 Timer 确保节流）
  void _scheduleProgressUpdate() {
    // 如果已有计时器在等待，不重复创建
    if (_progressTimer != null) return;

    _progressTimer = Timer(const Duration(milliseconds: _progressThrottleMs), () {
      _progressTimer = null;
      final bytes = uploadedBytes;
      final total = totalBytes;
      // 在 UI 线程调用回调
      onProgress?.call(bytes, total);
    });
  }

  /// 完成分块上传
  Future<bool> complete() async {
    if (uploadId == null) {
      errorMessage = 'UploadId 为空，请先调用 initiate()';
      logError('[AliyunMultipartUploadManager] $errorMessage');
      return false;
    }

    try {
      _setStatus(AliyunMultipartUploadStatus.completing);
      log('[AliyunMultipartUploadManager] 开始完成分块上传, 共 ${uploadedParts.length} 个分块');

      // 构建请求体 XML
      final completeXml = StringBuffer();
      completeXml.write('<?xml version="1.0" encoding="UTF-8"?>');
      completeXml.write('<CompleteMultipartUpload>');

      final sortedParts = uploadedParts.values.toList()
        ..sort((a, b) => a.partNumber.compareTo(b.partNumber));
      for (final part in sortedParts) {
        completeXml.write('<Part>');
        completeXml.write('<PartNumber>${part.partNumber}</PartNumber>');
        completeXml.write('<ETag>${part.eTag}</ETag>');
        completeXml.write('</Part>');
      }

      completeXml.write('</CompleteMultipartUpload>');

      final completeBody = completeXml.toString();
      final completeBodyBytes = utf8.encode(completeBody);

      // 计算Content-MD5
      final completeMd5 = md5.convert(completeBodyBytes);
      final completeMd5Str = base64Encode(completeMd5.bytes);

      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final signature = await _generateSignature(
        method: 'POST',
        objectKey: objectKey,
        extraHeaders: {
          'Content-Type': 'application/xml',
          'Content-MD5': completeMd5Str,
        },
        queryParams: {'uploadId': uploadId!},
      );

      final headers = {
        'Authorization': signature,
        'Content-Type': 'application/xml',
        'Content-MD5': completeMd5Str,
        'date': httpDate,
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD',
        'host': _host,
      };

      final url = 'https://$_host/${_encodePath(objectKey)}?uploadId=$uploadId';
      final response = await dio.post(
        url,
        data: completeBodyBytes,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        log('[AliyunMultipartUploadManager] 分块上传完成成功');
        _setStatus(AliyunMultipartUploadStatus.completed);
        return true;
      } else {
        errorMessage = '完成分块上传失败: ${response.statusCode}';
        logError('[AliyunMultipartUploadManager] $errorMessage, 响应: ${response.data}');
        _setStatus(AliyunMultipartUploadStatus.failed);
        return false;
      }
    } catch (e, stack) {
      errorMessage = '完成分块上传异常: $e';
      logError('[AliyunMultipartUploadManager] $errorMessage', stack);
      _setStatus(AliyunMultipartUploadStatus.failed);
      return false;
    }
  }

  /// 取消分块上传
  Future<bool> abort() async {
    if (uploadId == null) {
      log('[AliyunMultipartUploadManager] UploadId 为空，无需取消');
      return true;
    }

    try {
      log('[AliyunMultipartUploadManager] 取消分块上传: $uploadId');

      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final signature = await _generateSignature(
        method: 'DELETE',
        objectKey: objectKey,
        queryParams: {'uploadId': uploadId!},
      );

      final headers = {
        'Authorization': signature,
        'date': httpDate,
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD',
        'host': _host,
      };

      final url = 'https://$_host/${_encodePath(objectKey)}?uploadId=$uploadId';
      final response = await dio.delete(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        log('[AliyunMultipartUploadManager] 取消分块上传成功');
        _setStatus(AliyunMultipartUploadStatus.cancelled);
        return true;
      } else {
        logError('[AliyunMultipartUploadManager] 取消分块上传失败: ${response.statusCode}');
        return false;
      }
    } catch (e, stack) {
      logError('[AliyunMultipartUploadManager] 取消分块上传异常: $e', stack);
      return false;
    }
  }

  /// 上传整个文件（封装好的完整流程，支持并行上传）
  Future<bool> uploadFile(
    File file, {
    void Function(int bytesUploaded, int totalBytes)? onProgress,
    void Function(AliyunMultipartUploadStatus status)? onStatusChanged,
    int concurrency = kDefaultParallelConcurrency,
  }) async {
    // 设置回调
    if (onProgress != null) {
      this.onProgress = onProgress;
    }
    if (onStatusChanged != null) {
      this.onStatusChanged = onStatusChanged;
    }

    // 重置进度节流计时器
    _progressTimer?.cancel();
    _progressTimer = null;

    // 获取文件大小
    totalBytes = await file.length();
    log('[AliyunMultipartUploadManager] 开始上传文件: ${file.path}, 大小: $totalBytes bytes');

    // 初始化
    if (!await initiate()) {
      return false;
    }

    // 读取并上传分块
    _setStatus(AliyunMultipartUploadStatus.uploading);
    final reader = FileChunkReader(chunkSize: chunkSize);

    final totalChunks = FileChunkReader.calculateChunkCount(totalBytes, chunkSize: chunkSize);
    log('[AliyunMultipartUploadManager] 开始并行上传 $totalChunks 个分块，并发数: $concurrency');

    // 收集所有分块数据
    final chunks = <FileChunk>[];
    await for (final chunk in reader.chunkStream(file)) {
      chunks.add(chunk);
    }

    // 并行上传分块
    int successCount = 0;
    int nextIndex = 0;
    final pendingTasks = <Future<bool>>[];
    bool hasError = false;

    while (nextIndex < chunks.length || pendingTasks.isNotEmpty) {
      // 填充任务队列直到达到并发上限
      while (nextIndex < chunks.length && pendingTasks.length < concurrency) {
        final chunk = chunks[nextIndex];
        final task = uploadPart(chunk.partNumber, chunk.data).then((success) {
          if (success) {
            successCount++;
          }
          return success;
        });
        pendingTasks.add(task);
        nextIndex++;
      }

      // 等待当前批次任务完成
      if (pendingTasks.isNotEmpty) {
        final results = await Future.wait(pendingTasks);
        pendingTasks.clear();

        // 如果有任何一个失败的，中止上传
        if (results.any((r) => !r)) {
          hasError = true;
          break;
        }
      }
    }

    if (hasError || successCount != totalChunks) {
      errorMessage = '部分分块上传失败: $successCount/$totalChunks';
      logError('[AliyunMultipartUploadManager] $errorMessage');
      await abort();
      return false;
    }

    log('[AliyunMultipartUploadManager] 分块上传完成, 成功: $successCount/$totalChunks');

    // 完成上传
    return await complete();
  }

  /// 获取已上传的分块列表（用于断点续传）
  List<AliyunUploadedPart> getUploadedParts() {
    return uploadedParts.values.toList()..sort((a, b) => a.partNumber.compareTo(b.partNumber));
  }

  /// 获取上传进度 (0.0 - 1.0)
  double getProgress() {
    if (totalBytes == 0) return 0.0;
    return uploadedBytes / totalBytes;
  }

  /// 获取已上传分块的 ETags（用于 Complete 请求）
  Map<int, String> getPartETags() {
    return {for (final part in uploadedParts.values) part.partNumber: part.eTag};
  }
}
