import 'package:dio/dio.dart';
import '../../utils/logger.dart';

class HttpClient {
  late final Dio _dio;

  HttpClient({
    String? baseUrl,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '',
        connectTimeout: connectTimeout ?? const Duration(seconds: 30),
        receiveTimeout: receiveTimeout ?? const Duration(seconds: 30),
        sendTimeout: sendTimeout ?? const Duration(seconds: 30),
      ),
    );
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    void Function(int, int)? onReceiveProgress,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
  }) async {
    logNetworkRequest('GET', path, queryParameters);
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(headers: headers, responseType: responseType),
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
      );
      _logResponse('GET', path, response);
      return response;
    } on DioException catch (e) {
      _logError('GET', path, e);
      rethrow;
    }
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    void Function(int, int)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    logNetworkRequest('POST', path, {'data': data, 'queryParams': queryParameters});
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      _logResponse('POST', path, response);
      return response;
    } on DioException catch (e) {
      _logError('POST', path, e);
      rethrow;
    }
  }

  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    void Function(int, int)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    logNetworkRequest('PUT', path, {'data': data, 'queryParams': queryParameters});
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      _logResponse('PUT', path, response);
      return response;
    } on DioException catch (e) {
      _logError('PUT', path, e);
      rethrow;
    }
  }

  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) async {
    logNetworkRequest('DELETE', path, {'data': data, 'queryParams': queryParameters});
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      _logResponse('DELETE', path, response);
      return response;
    } on DioException catch (e) {
      _logError('DELETE', path, e);
      rethrow;
    }
  }

  Future<Response> download(
    String url,
    dynamic savePath, {
    void Function(int, int)? onReceiveProgress,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) async {
    logNetworkRequest('DOWNLOAD', url, {'savePath': savePath.toString()});
    try {
      final response = await _dio.download(
        url,
        savePath,
        onReceiveProgress: onReceiveProgress,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      logNetworkResponse(url, response.statusCode ?? 0, 'Download completed');
      return response;
    } on DioException catch (e) {
      _logError('DOWNLOAD', url, e);
      rethrow;
    }
  }

  void _logResponse(String method, String path, Response response) {
    final dataStr = response.data?.toString() ?? '';
    final truncatedData = dataStr.length > 500 ? '${dataStr.substring(0, 500)}...' : dataStr;
    logNetworkResponse(path, response.statusCode ?? 0, truncatedData);
  }

  void _logError(String method, String path, DioException e) {
    String errorInfo = 'type: ${e.type}, message: ${e.message}';

    if (e.response != null) {
      errorInfo += ', status: ${e.response!.statusCode}';
      if (e.response!.data != null) {
        final dataStr = e.response!.data.toString();
        // 增加响应日志长度限制，便于调试
        final truncated = dataStr.length > 5000 ? '${dataStr.substring(0, 5000)}...' : dataStr;
        errorInfo += ', response: $truncated';
      }
    }

    logNetworkError(path, errorInfo);
  }
}
