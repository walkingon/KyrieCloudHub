import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../models/platform_credential.dart';
import '../../../utils/logger.dart';
import '../../api/cloud_platform_api.dart';

/// 分块下载状态
enum AliyunMultipartDownloadStatus {
  idle,
  initiating,
  downloading,
  completed,
  failed,
  cancelled,
}

/// 单个分块下载信息
class AliyunDownloadChunk {
  final int partNumber;
  final int start;
  final int end;
  final int size;
  Uint8List? data;

  AliyunDownloadChunk({
    required this.partNumber,
    required this.start,
    required this.end,
  }) : size = end - start + 1;
}

/// 阿里云OSS分块下载管理器
///
/// 负责管理大文件分块串行下载：
/// 1. 获取文件大小 (HEAD请求)
/// 2. 计算分块范围
/// 3. 串行下载各分块 (HTTP Range)
/// 4. 合并分块到文件
class AliyunMultipartDownloadManager {
  final PlatformCredential credential;
  final Dio dio;
  final String bucketName;
  final String region;
  final String objectKey;
  final int chunkSize;

  /// 文件总大小
  int _totalBytes = 0;

  /// 已下载的字节数
  int _downloadedBytes = 0;

  /// 分块列表
  final List<AliyunDownloadChunk> _chunks = [];

  /// 当前状态
  AliyunMultipartDownloadStatus status = AliyunMultipartDownloadStatus.idle;

  /// 错误信息
  String? errorMessage;

  /// 进度回调
  void Function(int bytesDownloaded, int totalBytes)? onProgress;

  /// 状态回调
  void Function(AliyunMultipartDownloadStatus status)? onStatusChanged;

  /// 签名方法回调
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

  AliyunMultipartDownloadManager({
    required this.credential,
    required this.dio,
    required this.bucketName,
    required this.region,
    required this.objectKey,
    this.chunkSize = kDefaultChunkSize,
  });

  /// 更新状态
  void _setStatus(AliyunMultipartDownloadStatus newStatus) {
    if (status != newStatus) {
      status = newStatus;
      logger.info('[AliyunMultipartDownloadManager] 状态变更: $newStatus');
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
      throw Exception('签名方法未设置');
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

  /// 对路径进行 URI 编码（不编码正斜杠）
  String _encodePath(String path) {
    return Uri.encodeComponent(path)
        .replaceAll('%2F', '/')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29');
  }

  /// 获取文件总大小
  Future<bool> _getFileSize() async {
    try {
      final signature = await _generateSignature(
        method: 'HEAD',
        objectKey: objectKey,
      );

      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final headers = {
        'Authorization': signature,
        'date': httpDate,
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD',
        'host': _host,
      };

      final url = 'https://$_host/${_encodePath(objectKey)}';
      final response = await dio.head(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        final contentLength = response.headers['content-length'];
        if (contentLength != null && contentLength.isNotEmpty) {
          _totalBytes = int.parse(contentLength.first);
          logger.info('[AliyunMultipartDownloadManager] 文件总大小: $_totalBytes bytes');
          return true;
        }
      }
      return false;
    } catch (e, stack) {
      logger.error('[AliyunMultipartDownloadManager] 获取文件大小失败: $e', stack);
      return false;
    }
  }

  /// 计算分块范围
  void _calculateChunks() {
    _chunks.clear();
    final totalChunks = (_totalBytes / chunkSize).ceil();

    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = min<int>(start + chunkSize - 1, _totalBytes - 1);
      _chunks.add(AliyunDownloadChunk(
        partNumber: i + 1,
        start: start,
        end: end,
      ));
    }

    logger.info('[AliyunMultipartDownloadManager] 分块数: ${_chunks.length}, 每块大小: $chunkSize bytes');
  }

  /// 下载单个分块
  Future<bool> _downloadChunk(AliyunDownloadChunk chunk) async {
    try {
      final signature = await _generateSignature(
        method: 'GET',
        objectKey: objectKey,
        extraHeaders: {'Range': 'bytes=${chunk.start}-${chunk.end}'},
      );

      final date = DateTime.now().toUtc();
      final iso8601DateTime = _formatIso8601DateTime(date);
      final httpDate = HttpDate.format(date);

      final headers = {
        'Authorization': signature,
        'date': httpDate,
        'x-oss-date': iso8601DateTime,
        'x-oss-content-sha256': 'UNSIGNED-PAYLOAD',
        'host': _host,
        'Range': 'bytes=${chunk.start}-${chunk.end}',
      };

      final url = 'https://$_host/${_encodePath(objectKey)}';
      final response = await dio.get(
        url,
        options: Options(headers: headers, responseType: ResponseType.stream),
      );

      if (response.statusCode == 206) {
        // 从 ResponseBody.stream 读取字节数据
        final stream = response.data as ResponseBody;
        chunk.data = await stream.stream.toList().then((chunks) {
          final allBytes = <int>[];
          for (final c in chunks) {
            allBytes.addAll(c);
          }
          return Uint8List.fromList(allBytes);
        });

        // 线程安全地更新进度
        _updateProgress(chunk.data!.length);

        logger.info('[AliyunMultipartDownloadManager] 分块 ${chunk.partNumber} 下载成功: ${chunk.data!.length} bytes');
        return true;
      } else {
        logger.error('[AliyunMultipartDownloadManager] 分块 ${chunk.partNumber} 下载失败: ${response.statusCode}');
        return false;
      }
    } catch (e, stack) {
      logger.error('[AliyunMultipartDownloadManager] 分块 ${chunk.partNumber} 下载异常: $e', stack);
      return false;
    }
  }

  /// 线程安全的进度更新（带节流）
  void _updateProgress(int bytesJustDownloaded) {
    _downloadedBytes += bytesJustDownloaded;

    // 使用 scheduleMicrotask 确保进度回调按顺序执行
    _scheduleProgressUpdate();
  }

  /// 安排进度更新（使用 Timer 确保节流）
  void _scheduleProgressUpdate() {
    // 如果已有计时器在等待，不重复创建
    if (_progressTimer != null) return;

    _progressTimer = Timer(const Duration(milliseconds: _progressThrottleMs), () {
      _progressTimer = null;
      final bytes = _downloadedBytes;
      final total = _totalBytes;
      // 在 UI 线程调用回调
      onProgress?.call(bytes, total);
    });
  }

  /// 合并分块到文件
  Future<bool> _mergeChunks(File outputFile) async {
    try {
      logger.info('[AliyunMultipartDownloadManager] 开始合并分块到文件: ${outputFile.path}');

      // 按分块号排序
      _chunks.sort((a, b) => a.partNumber.compareTo(b.partNumber));

      // 使用 RandomAccessFile 进行顺序写入
      final raf = await outputFile.open(mode: FileMode.writeOnly);
      try {
        for (final chunk in _chunks) {
          if (chunk.data != null) {
            await raf.writeFrom(chunk.data!);
            // 释放内存
            chunk.data = null;
          }
        }
      } finally {
        await raf.close();
      }

      logger.info('[AliyunMultipartDownloadManager] 文件合并完成');
      return true;
    } catch (e, stack) {
      logger.error('[AliyunMultipartDownloadManager] 合并分块失败: $e', stack);
      return false;
    }
  }

  /// 下载文件（支持并行下载）
  Future<bool> downloadFile(
    File outputFile, {
    void Function(int bytesDownloaded, int totalBytes)? onProgress,
    void Function(AliyunMultipartDownloadStatus status)? onStatusChanged,
    int concurrency = kDefaultParallelConcurrency,
  }) async {
    // 设置回调
    if (onProgress != null) this.onProgress = onProgress;
    if (onStatusChanged != null) this.onStatusChanged = onStatusChanged;
    // 重置进度节流计时器
    _progressTimer?.cancel();
    _progressTimer = null;

    try {
      _setStatus(AliyunMultipartDownloadStatus.initiating);
      logger.info('[AliyunMultipartDownloadManager] 开始下载文件: $objectKey');

      // 1. 获取文件大小
      if (!await _getFileSize()) {
        errorMessage = '获取文件大小失败';
        _setStatus(AliyunMultipartDownloadStatus.failed);
        return false;
      }

      // 2. 计算分块
      _calculateChunks();

      // 3. 并行下载分块
      _setStatus(AliyunMultipartDownloadStatus.downloading);
      logger.info('[AliyunMultipartDownloadManager] 开始并行下载 ${_chunks.length} 个分块，并发数: $concurrency');

      int nextIndex = 0;
      final pendingTasks = <Future<bool>>[];
      bool hasError = false;

      while (nextIndex < _chunks.length || pendingTasks.isNotEmpty) {
        // 填充任务队列直到达到并发上限
        while (nextIndex < _chunks.length && pendingTasks.length < concurrency) {
          final chunk = _chunks[nextIndex];
          final task = _downloadChunk(chunk).then((success) {
            return success;
          });
          pendingTasks.add(task);
          nextIndex++;
        }

        // 等待当前批次任务完成
        if (pendingTasks.isNotEmpty) {
          final results = await Future.wait(pendingTasks);
          pendingTasks.clear();

          // 如果有任何一个失败的，中止下载
          if (results.any((r) => !r)) {
            hasError = true;
            break;
          }
        }
      }

      if (hasError || _chunks.any((c) => c.data == null)) {
        errorMessage = '部分分块下载失败';
        logger.error(errorMessage!);
        _setStatus(AliyunMultipartDownloadStatus.failed);
        return false;
      }

      // 4. 合并分块
      if (!await _mergeChunks(outputFile)) {
        errorMessage = '合并分块失败';
        _setStatus(AliyunMultipartDownloadStatus.failed);
        return false;
      }

      _setStatus(AliyunMultipartDownloadStatus.completed);
      logger.info('[AliyunMultipartDownloadManager] 下载完成: ${outputFile.path}');
      return true;
    } catch (e, stack) {
      errorMessage = '下载异常: $e';
      logger.error(errorMessage ?? '未知错误', stack);
      _setStatus(AliyunMultipartDownloadStatus.failed);
      return false;
    }
  }

  /// 取消下载
  Future<void> cancel() async {
    _setStatus(AliyunMultipartDownloadStatus.cancelled);
    logger.info('[AliyunMultipartDownloadManager] 下载已取消');
  }

  /// 获取下载进度 (0.0 - 1.0)
  double getProgress() {
    if (_totalBytes == 0) return 0.0;
    return _downloadedBytes / _totalBytes;
  }
}
