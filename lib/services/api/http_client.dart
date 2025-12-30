import 'package:dio/dio.dart';
import '../../utils/logger.dart' as logger;

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
  }) async {
    logger.log('[HTTP GET] Request: $path, params: $queryParameters');
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(headers: headers),
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
    logger.log('[HTTP POST] Request: $path, data: $data');
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
    logger.log('[HTTP PUT] Request: $path, data: $data');
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
    logger.log('[HTTP DELETE] Request: $path, data: $data');
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
    logger.log('[HTTP DOWNLOAD] Request: $url -> $savePath');
    try {
      final response = await _dio.download(
        url,
        savePath,
        onReceiveProgress: onReceiveProgress,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      logger.log('[HTTP DOWNLOAD] Completed: $url, status: ${response.statusCode}');
      return response;
    } on DioException catch (e) {
      _logError('DOWNLOAD', url, e);
      rethrow;
    }
  }

  void _logResponse(String method, String path, Response response) {
    logger.log(
      '[HTTP $method] Response: $path, status: ${response.statusCode}, '
      'data: ${response.data?.toString().substring(0, 500)}',
    );
  }

  void _logError(String method, String path, DioException e) {
    logger.log(
      '[HTTP $method] Error: $path, type: ${e.type}, message: ${e.message}',
    );
  }
}
