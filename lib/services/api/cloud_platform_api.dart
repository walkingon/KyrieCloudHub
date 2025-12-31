import 'dart:io';

import '../../models/bucket.dart';
import '../../models/object_file.dart';

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? errorMessage;
  final int? statusCode;

  ApiResponse.success(this.data)
      : success = true,
        errorMessage = null,
        statusCode = null;

  ApiResponse.error(this.errorMessage, {this.statusCode})
      : success = false,
        data = null;
}

class ListObjectsResult {
  final List<ObjectFile> objects;
  final bool isTruncated;
  final String? nextMarker;

  ListObjectsResult({
    required this.objects,
    this.isTruncated = false,
    this.nextMarker,
  });
}

abstract class ICloudPlatformApi {
  Future<ApiResponse<List<Bucket>>> listBuckets();

  Future<ApiResponse<ListObjectsResult>> listObjects({
    required String bucketName,
    required String region,
    String prefix = '',
    String delimiter = '/',
    int maxKeys = 1000,
    String? marker,
  });

  Future<ApiResponse<void>> uploadObject({
    required String bucketName,
    required String region,
    required String objectKey,
    required List<int> data,
    void Function(int sent, int total)? onProgress,
  });

  /// 分块上传文件
  ///
  /// [file] 要上传的本地文件
  /// [bucketName] 存储桶名称
  /// [region] 地域
  /// [objectKey] 对象键
  /// [chunkSize] 分块大小 (字节), 默认 1MB
  /// [onProgress] 进度回调 (已上传字节数, 总字节数)
  /// [onStatusChanged] 状态变更回调
  Future<ApiResponse<void>> uploadObjectMultipart({
    required String bucketName,
    required String region,
    required String objectKey,
    required File file,
    int chunkSize = 64 * 1024 * 1024, // 64MB 分块
    void Function(int sent, int total)? onProgress,
    void Function(int status)? onStatusChanged,
  });

  Future<ApiResponse<List<int>>> downloadObject({
    required String bucketName,
    required String region,
    required String objectKey,
    void Function(int received, int total)? onProgress,
  });

  Future<ApiResponse<void>> deleteObject({
    required String bucketName,
    required String region,
    required String objectKey,
  });

  Future<ApiResponse<void>> deleteObjects({
    required String bucketName,
    required String region,
    required List<String> objectKeys,
  });

  /// 创建文件夹（通过上传一个0字节的对象，key以/结尾）
  Future<ApiResponse<void>> createFolder({
    required String bucketName,
    required String region,
    required String folderName,
    String prefix = '',
  });

  /// 重命名对象（通过复制到新名称 + 删除原对象实现）
  ///
  /// [sourceKey] 原对象key
  /// [newName] 新名称（不含路径）
  /// [prefix] 当前目录前缀
  Future<ApiResponse<void>> renameObject({
    required String bucketName,
    required String region,
    required String sourceKey,
    required String newName,
    String prefix = '',
  });

  /// 递归删除文件夹及其所有内容
  Future<ApiResponse<void>> deleteFolder({
    required String bucketName,
    required String region,
    required String folderKey,
  });
}