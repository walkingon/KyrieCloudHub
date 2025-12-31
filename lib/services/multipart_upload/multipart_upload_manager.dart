import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../models/platform_credential.dart';
import '../../utils/logger.dart';
import 'file_chunk_reader.dart';

/// 已上传分块信息
class UploadedPart {
  final int partNumber;
  final String eTag;
  final int size;

  UploadedPart({
    required this.partNumber,
    required this.eTag,
    required this.size,
  });

  factory UploadedPart.fromXml(XmlElement element) {
    final partNumber = int.parse(element.findElements('PartNumber').first.innerText);
    final eTag = element.findElements('ETag').first.innerText.replaceAll('"', '');
    final size = int.parse(element.findElements('Size').first.innerText);

    return UploadedPart(
      partNumber: partNumber,
      eTag: eTag,
      size: size,
    );
  }

  Map<String, dynamic> toJson() => {
    'partNumber': partNumber,
    'eTag': eTag,
    'size': size,
  };
}

/// 分块上传状态
enum MultipartUploadStatus {
  idle,
  initiating,
  uploading,
  completing,
  completed,
  failed,
  cancelled,
}

/// 分块上传管理器
///
/// 负责管理整个分块上传流程：
/// 1. 初始化分块上传 (Initiate Multipart Upload)
/// 2. 上传分块 (Upload Part)
/// 3. 完成分块上传 (Complete Multipart Upload)
/// 4. 取消分块上传 (Abort Multipart Upload)
class MultipartUploadManager {
  final PlatformCredential credential;
  final Dio dio;  // 改为直接使用 Dio
  final String bucketName;
  final String region;
  final String objectKey;
  final int chunkSize;

  /// 上传任务ID
  String? uploadId;

  /// 已上传的分块信息
  final Map<int, UploadedPart> uploadedParts = {};

  /// 当前状态
  MultipartUploadStatus status = MultipartUploadStatus.idle;

  /// 已上传的字节数
  int uploadedBytes = 0;

  /// 总文件大小
  int totalBytes = 0;

  /// 错误信息
  String? errorMessage;

  /// 进度回调
  void Function(int bytesUploaded, int totalBytes)? onProgress;

  /// 状态回调
  void Function(MultipartUploadStatus status)? onStatusChanged;

  /// 签名方法回调（由外部传入，避免重复签名逻辑）
  Future<String> Function(String method, String path, {Map<String, String>? queryParams})?
      getSignature;

  /// 签名方法回调（带额外头部，用于需要额外头部的请求如 uploadPart）
  Future<String> Function(String method, String path, Map<String, String> extraHeaders,
      {Map<String, String>? queryParams})? getSignatureWithHeaders;

  MultipartUploadManager({
    required this.credential,
    required this.dio,
    required this.bucketName,
    required this.region,
    required this.objectKey,
    this.chunkSize = FileChunkReader.defaultChunkSize,
  });

  /// 获取请求主机
  String get _host => '$bucketName.cos.$region.myqcloud.com';

  /// 更新状态
  void _setStatus(MultipartUploadStatus newStatus) {
    if (status != newStatus) {
      status = newStatus;
      log('[MultipartUploadManager] 状态变更: $newStatus');
      onStatusChanged?.call(newStatus);
    }
  }

  /// 初始化分块上传
  Future<bool> initiate() async {
    try {
      _setStatus(MultipartUploadStatus.initiating);
      log('[MultipartUploadManager] 开始初始化分块上传: $objectKey');

      if (getSignature == null) {
        throw Exception('签名方法未设置，请传入 getSignature 回调');
      }
      final signature = await getSignature!('POST', '/$objectKey', queryParams: {'uploads': ''});

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;

      // q-url-param-list 只需要参数名，不需要编码
      final urlParamList = 'uploads';

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$now;$end&q-key-time=$now;$end&q-header-list=date;host&q-url-param-list=$urlParamList&q-signature=$signature',
        'Host': _host,
        'Content-Type': 'application/octet-stream',
        'Date': HttpDate.format(DateTime.now().toUtc()),
      };

      final url = 'https://$_host/$objectKey?uploads';
      final response = await dio.post(url, data: [], options: Options(headers: headers));

      if (response.statusCode == 200) {
        // 解析XML响应获取 UploadId
        log('[MultipartUploadManager] response.data type: ${response.data.runtimeType}');

        XmlDocument document;
        if (response.data is XmlDocument) {
          document = response.data as XmlDocument;
        } else {
          final responseData = response.data?.toString() ?? '';
          log('[MultipartUploadManager] 初始化响应: $responseData');
          document = XmlDocument.parse(responseData);
        }

        // 从根元素查找 UploadId 子元素
        final uploadIdElement = document.rootElement.findElements('UploadId').first;
        uploadId = uploadIdElement.innerText;
        log('[MultipartUploadManager] 初始化成功, UploadId: $uploadId');
        uploadedParts.clear();
        uploadedBytes = 0;
        return true;
      } else {
        errorMessage = '初始化分块上传失败: ${response.statusCode}';
        logError('[MultipartUploadManager] $errorMessage');
        _setStatus(MultipartUploadStatus.failed);
        return false;
      }
    } catch (e, stack) {
      errorMessage = '初始化分块上传异常: $e';
      logError('[MultipartUploadManager] $errorMessage', stack);
      _setStatus(MultipartUploadStatus.failed);
      return false;
    }
  }

  /// 上传单个分块
  Future<bool> uploadPart(int partNumber, Uint8List data) async {
    if (uploadId == null) {
      errorMessage = 'UploadId 为空，请先调用 initiate()';
      logError('[MultipartUploadManager] $errorMessage');
      return false;
    }

    try {
      // 计算 Content-MD5（需要先计算，因为签名需要用到）
      final digest = md5.convert(data);
      final md5Base64 = base64Encode(digest.bytes);

      final queryParams = {
        'partNumber': partNumber.toString(),
        'uploadId': uploadId!,
      };

      if (getSignatureWithHeaders == null) {
        throw Exception('签名方法未设置，请传入 getSignatureWithHeaders 回调');
      }

      // 传递参与签名的额外头部（content-length 和 content-md5）
      final signature = await getSignatureWithHeaders!(
        'PUT',
        '/$objectKey',
        {
          'content-length': data.length.toString(),
          'content-md5': md5Base64,
        },
        queryParams: queryParams,
      );

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$now;$end&q-key-time=$now;$end&q-header-list=content-length;content-md5;date;host&q-url-param-list=partnumber;uploadid&q-signature=$signature',
        'Host': _host,
        'Content-Type': 'application/octet-stream',
        'Content-MD5': md5Base64,
        'Content-Length': data.length.toString(),
        'Date': HttpDate.format(DateTime.now().toUtc()),
      };

      final url = 'https://$_host/$objectKey?partNumber=$partNumber&uploadId=$uploadId';
      final response = await dio.put(
        url,
        data: data,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        // 获取 ETag - 从响应头中获取
        String eTag = '';
        final etagValues = response.headers['etag'];
        if (etagValues != null && etagValues.isNotEmpty) {
          eTag = etagValues.first.replaceAll('"', '');
        }

        if (eTag.isNotEmpty) {
          uploadedParts[partNumber] = UploadedPart(
            partNumber: partNumber,
            eTag: eTag,
            size: data.length,
          );
        }

        uploadedBytes += data.length;
        onProgress?.call(uploadedBytes, totalBytes);

        log('[MultipartUploadManager] 分块 $partNumber 上传成功, ETag: $eTag');
        return true;
      } else {
        logError('[MultipartUploadManager] 分块 $partNumber 上传失败: ${response.statusCode}');
        return false;
      }
    } catch (e, stack) {
      logError('[MultipartUploadManager] 分块 $partNumber 上传异常: $e', stack);
      return false;
    }
  }

  /// 完成分块上传
  Future<bool> complete() async {
    if (uploadId == null) {
      errorMessage = 'UploadId 为空，请先调用 initiate()';
      logError('[MultipartUploadManager] $errorMessage');
      return false;
    }

    try {
      _setStatus(MultipartUploadStatus.completing);
      log('[MultipartUploadManager] 开始完成分块上传, 共 ${uploadedParts.length} 个分块');

      // 构建请求体 XML
      final partsXml = StringBuffer();
      partsXml.write('<?xml version="1.0" encoding="UTF-8"?>');
      partsXml.write('<CompleteMultipartUpload>');

      final sortedParts = uploadedParts.values.toList()..sort((a, b) => a.partNumber.compareTo(b.partNumber));
      for (final part in sortedParts) {
        partsXml.write('<Part>');
        partsXml.write('<PartNumber>${part.partNumber}</PartNumber>');
        partsXml.write('<ETag>"${part.eTag}"</ETag>');
        partsXml.write('</Part>');
      }

      partsXml.write('</CompleteMultipartUpload>');

      final queryParams = {'uploadId': uploadId!};
      if (getSignature == null) {
        throw Exception('签名方法未设置，请传入 getSignature 回调');
      }
      final signature = await getSignature!('POST', '/$objectKey', queryParams: queryParams);

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$now;$end&q-key-time=$now;$end&q-header-list=date;host&q-url-param-list=uploadid&q-signature=$signature',
        'Host': _host,
        'Content-Type': 'application/xml',
        'Date': HttpDate.format(DateTime.now().toUtc()),
      };

      final url = 'https://$_host/$objectKey?uploadId=$uploadId';
      final response = await dio.post(
        url,
        data: utf8.encode(partsXml.toString()),
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        log('[MultipartUploadManager] 分块上传完成成功');
        _setStatus(MultipartUploadStatus.completed);
        return true;
      } else {
        errorMessage = '完成分块上传失败: ${response.statusCode}';
        logError('[MultipartUploadManager] $errorMessage, 响应: ${response.data}');
        _setStatus(MultipartUploadStatus.failed);
        return false;
      }
    } catch (e, stack) {
      errorMessage = '完成分块上传异常: $e';
      logError('[MultipartUploadManager] $errorMessage', stack);
      _setStatus(MultipartUploadStatus.failed);
      return false;
    }
  }

  /// 取消分块上传
  Future<bool> abort() async {
    if (uploadId == null) {
      log('[MultipartUploadManager] UploadId 为空，无需取消');
      return true;
    }

    try {
      log('[MultipartUploadManager] 取消分块上传: $uploadId');

      final queryParams = {'uploadId': uploadId!};
      if (getSignature == null) {
        throw Exception('签名方法未设置，请传入 getSignature 回调');
      }
      final signature = await getSignature!('DELETE', '/$objectKey', queryParams: queryParams);

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final end = now + 3600;

      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=$now;$end&q-key-time=$now;$end&q-header-list=date;host&q-url-param-list=uploadid&q-signature=$signature',
        'Host': _host,
        'Date': HttpDate.format(DateTime.now().toUtc()),
      };

      final url = 'https://$_host/$objectKey?uploadId=$uploadId';
      final response = await dio.delete(url, options: Options(headers: headers));

      if (response.statusCode == 204) {
        log('[MultipartUploadManager] 取消分块上传成功');
        _setStatus(MultipartUploadStatus.cancelled);
        return true;
      } else {
        logError('[MultipartUploadManager] 取消分块上传失败: ${response.statusCode}');
        return false;
      }
    } catch (e, stack) {
      logError('[MultipartUploadManager] 取消分块上传异常: $e', stack);
      return false;
    }
  }

  /// 上传整个文件（封装好的完整流程）
  Future<bool> uploadFile(
    File file, {
    void Function(int bytesUploaded, int totalBytes)? onProgress,
    void Function(MultipartUploadStatus status)? onStatusChanged,
  }) async {
    // 设置回调
    if (onProgress != null) {
      this.onProgress = onProgress;
    }
    if (onStatusChanged != null) {
      this.onStatusChanged = onStatusChanged;
    }

    // 获取文件大小
    totalBytes = await file.length();
    log('[MultipartUploadManager] 开始上传文件: ${file.path}, 大小: $totalBytes bytes');

    // 初始化
    if (!await initiate()) {
      return false;
    }

    // 读取并上传分块
    _setStatus(MultipartUploadStatus.uploading);
    final reader = FileChunkReader(chunkSize: chunkSize);

    int successCount = 0;
    final totalChunks = FileChunkReader.calculateChunkCount(totalBytes, chunkSize: chunkSize);
    log('[MultipartUploadManager] 开始上传 $totalChunks 个分块');

    // 使用 Stream 方式读取分块
    await for (final chunk in reader.chunkStream(file)) {
      final success = await uploadPart(chunk.partNumber, chunk.data);
      if (success) {
        successCount++;
      } else {
        logError('[MultipartUploadManager] 分块 ${chunk.partNumber} 上传失败');
        // 可以选择继续上传其他分块或中断
      }
    }

    log('[MultipartUploadManager] 分块上传完成, 成功: $successCount/$totalChunks');

    if (uploadedParts.length != totalChunks) {
      errorMessage = '部分分块上传失败: $successCount/$totalChunks';
      logError('[MultipartUploadManager] $errorMessage');
      await abort();
      return false;
    }

    // 完成上传
    return await complete();
  }

  /// 获取已上传的分块列表（用于断点续传）
  List<UploadedPart> getUploadedParts() {
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
