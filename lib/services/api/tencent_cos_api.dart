import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../models/bucket.dart';
import '../../models/object_file.dart';
import '../../models/platform_credential.dart';
import 'cloud_platform_api.dart';
import 'http_client.dart';

class TencentCosApi implements ICloudPlatformApi {
  final PlatformCredential credential;
  final HttpClient httpClient;

  TencentCosApi(this.credential, this.httpClient);

  // 腾讯云签名算法实现
  String _getSignature(
    String method,
    String path,
    Map<String, String> headers,
    String secretKey,
  ) {
    // 简化版签名，实际需要更完整的实现
    final canonicalRequest = _buildCanonicalRequest(method, path, headers);
    final stringToSign = 'sha1\n$canonicalRequest';
    final key = utf8.encode(secretKey);
    final hmac = Hmac(sha1, key);
    final signature = hmac.convert(utf8.encode(stringToSign));
    return base64.encode(signature.bytes);
  }

  String _buildCanonicalRequest(
    String method,
    String path,
    Map<String, String> headers,
  ) {
    // 构建规范请求
    final sortedHeaders = headers.keys.toList()..sort();
    final canonicalHeaders = sortedHeaders
        .map((key) => '$key:${headers[key]}')
        .join('\n');
    return '$method\n$path\n\n$canonicalHeaders\n';
  }

  @override
  Future<ApiResponse<List<Bucket>>> listBuckets() async {
    try {
      final url = 'https://cos.${credential.region}.myqcloud.com/';
      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-key-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-header-list=&q-url-param-list=&q-signature=${_getSignature('GET', '/', {}, credential.secretKey)}',
        'Content-Type': 'application/xml',
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
      final url =
          'https://$bucketName.cos.$region.myqcloud.com/?prefix=$prefix&delimiter=$delimiter&max-keys=$maxKeys${marker != null ? '&marker=$marker' : ''}';
      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-key-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-header-list=&q-url-param-list=&q-signature=${_getSignature('GET', '/?prefix=$prefix&delimiter=$delimiter&max-keys=$maxKeys${marker != null ? '&marker=$marker' : ''}', {}, credential.secretKey)}',
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
      final url = 'https://$bucketName.cos.$region.myqcloud.com/$objectKey';
      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-key-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-header-list=&q-url-param-list=&q-signature=${_getSignature('PUT', '/$objectKey', {}, credential.secretKey)}',
        'Content-Type': 'application/octet-stream',
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
      final url = 'https://$bucketName.cos.$region.myqcloud.com/$objectKey';
      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-key-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-header-list=&q-url-param-list=&q-signature=${_getSignature('GET', '/$objectKey', {}, credential.secretKey)}',
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
      final url = 'https://$bucketName.cos.$region.myqcloud.com/$objectKey';
      final headers = {
        'Authorization':
            'q-sign-algorithm=sha1&q-ak=${credential.secretId}&q-sign-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-key-time=${DateTime.now().millisecondsSinceEpoch ~/ 1000}&q-header-list=&q-url-param-list=&q-signature=${_getSignature('DELETE', '/$objectKey', {}, credential.secretKey)}',
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
}
