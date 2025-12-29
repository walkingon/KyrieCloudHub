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
}