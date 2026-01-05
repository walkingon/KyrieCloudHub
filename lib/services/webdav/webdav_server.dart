import 'dart:convert';
import 'dart:io';
import '../../models/object_file.dart';
import '../../models/platform_type.dart';
import '../../models/platform_credential.dart';
import '../cloud_platform_factory.dart';
import '../../utils/logger.dart';

/// WebDAV服务器配置
class WebdavServerConfig {
  final String bucketName;
  final String region;
  final int port;
  final PlatformType platform;
  final PlatformCredential credential;
  final CloudPlatformFactory factory;

  WebdavServerConfig({
    required this.bucketName,
    required this.region,
    required this.port,
    required this.platform,
    required this.credential,
    required this.factory,
  });
}

/// WebDAV响应
class WebdavResponse {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  WebdavResponse({
    required this.statusCode,
    this.headers = const {},
    required this.bodyBytes,
  });

  factory WebdavResponse.ok({List<int> bodyBytes = const [], Map<String, String> headers = const {}}) {
    return WebdavResponse(statusCode: 200, headers: headers, bodyBytes: bodyBytes);
  }

  factory WebdavResponse.created({List<int> bodyBytes = const [], Map<String, String> headers = const {}}) {
    return WebdavResponse(statusCode: 201, headers: headers, bodyBytes: bodyBytes);
  }

  factory WebdavResponse.noContent() {
    return WebdavResponse(statusCode: 204, headers: {}, bodyBytes: []);
  }

  factory WebdavResponse.badRequest({List<int> bodyBytes = const [], String? body}) {
    final bytes = bodyBytes.isEmpty && body != null ? utf8.encode(body) : bodyBytes;
    return WebdavResponse(statusCode: 400, headers: {}, bodyBytes: bytes);
  }

  factory WebdavResponse.notFound({List<int> bodyBytes = const [], String? body}) {
    final bytes = bodyBytes.isEmpty && body != null ? utf8.encode(body) : bodyBytes;
    return WebdavResponse(statusCode: 404, headers: {}, bodyBytes: bytes);
  }

  factory WebdavResponse.methodNotAllowed({List<int> bodyBytes = const [], String? body}) {
    final bytes = bodyBytes.isEmpty && body != null ? utf8.encode(body) : bodyBytes;
    return WebdavResponse(statusCode: 405, headers: {}, bodyBytes: bytes);
  }

  factory WebdavResponse.conflict({List<int> bodyBytes = const [], String? body}) {
    final bytes = bodyBytes.isEmpty && body != null ? utf8.encode(body) : bodyBytes;
    return WebdavResponse(statusCode: 409, headers: {}, bodyBytes: bytes);
  }

  factory WebdavResponse.serverError({List<int> bodyBytes = const [], String? body}) {
    final bytes = bodyBytes.isEmpty && body != null ? utf8.encode(body) : bodyBytes;
    return WebdavResponse(statusCode: 500, headers: {}, bodyBytes: bytes);
  }
}

/// WebDAV协议处理器
class WebdavProtocolHandler {
  final WebdavServerConfig config;

  WebdavProtocolHandler({required this.config});

  /// 处理请求
  Future<WebdavResponse> handleRequest(HttpRequest request) async {
    final method = request.method.toUpperCase();
    final path = request.uri.path;

    logUi('WebDAV: Received $method request for: $path');

    try {
      switch (method) {
        case 'OPTIONS':
          return _handleOptions();
        case 'PROPFIND':
          return await _handlePropfind(request, path);
        case 'GET':
          return await _handleGet(path);
        case 'HEAD':
          return await _handleHead(path);
        case 'PUT':
          return await _handlePut(request, path);
        case 'MKCOL':
          return await _handleMkcol(path);
        case 'DELETE':
          return await _handleDelete(path);
        case 'COPY':
          return await _handleCopy(request, path);
        case 'MOVE':
          return await _handleMove(request, path);
        default:
          return WebdavResponse.methodNotAllowed(body: 'Method $method not allowed');
      }
    } catch (e, stack) {
      logError('WebDAV request error: $e\n$stack');
      return WebdavResponse.serverError(body: e.toString());
    }
  }

  /// 处理OPTIONS请求
  WebdavResponse _handleOptions() {
    return WebdavResponse.ok(
      headers: {
        'DAV': '1, 2',
        'Allow': 'OPTIONS, GET, HEAD, PROPFIND, MKCOL, PUT, DELETE, COPY, MOVE',
        'Content-Length': '0',
      },
    );
  }

  /// 处理PROPFIND请求 - 获取文件/目录属性
  Future<WebdavResponse> _handlePropfind(HttpRequest request, String path) async {
    final api = config.factory.createApi(config.platform, credential: config.credential);
    if (api == null) {
      return WebdavResponse.serverError(body: 'Failed to create API');
    }

    // 解析路径
    final relativePath = _getRelativePath(path);

    try {
      final result = await api.listObjects(
        bucketName: config.bucketName,
        region: config.region,
        prefix: relativePath.isEmpty ? '' : relativePath,
        delimiter: '/',
        maxKeys: 1000,
      );

      if (!result.success) {
        return WebdavResponse.serverError(bodyBytes: utf8.encode(result.errorMessage ?? 'Failed to list objects'));
      }

      final objects = result.data?.objects ?? [];
      final xmlResponse = _buildPropfindResponse(relativePath, objects);
      final xmlBytes = utf8.encode(xmlResponse);

      return WebdavResponse.ok(
        bodyBytes: xmlBytes,
        headers: {
          'Content-Type': 'application/xml',
          'Content-Length': xmlBytes.length.toString(),
        },
      );
    } catch (e) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode(e.toString()));
    }
  }

  /// 构建PROPFIND XML响应
  String _buildPropfindResponse(String prefix, List<ObjectFile> objects) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="utf-8"?>\n');
    buffer.write('<d:multistatus xmlns:d="DAV:">\n');

    // 当前路径
    buffer.write('  <d:response>\n');
    buffer.write('    <d:href>${Uri.encodeComponent(prefix.isEmpty ? '/' : prefix)}</d:href>\n');
    buffer.write('    <d:propstat>\n');
    buffer.write('      <d:prop>\n');
    buffer.write('        <d:displayname>${prefix.isEmpty ? 'root' : prefix.split('/').last}</d:displayname>\n');
    buffer.write('        <d:creationdate>${DateTime.now().toIso8601String()}</d:creationdate>\n');
    buffer.write('        <d:getlastmodified>${DateTime.now().toUtc().toIso8601String()}</d:getlastmodified>\n');
    buffer.write('      </d:prop>\n');
    buffer.write('      <d:status>HTTP/1.1 200 OK</d:status>\n');
    buffer.write('    </d:propstat>\n');
    buffer.write('  </d:response>\n');

    // 子文件/目录
    for (final obj in objects) {
      final href = prefix.isEmpty ? '/${obj.name}' : '$prefix/${obj.name}';
      final encodedHref = Uri.encodeComponent(href);

      buffer.write('  <d:response>\n');
      buffer.write('    <d:href>$encodedHref</d:href>\n');
      buffer.write('    <d:propstat>\n');
      buffer.write('      <d:prop>\n');
      buffer.write('        <d:displayname>${obj.name}</d:displayname>\n');
      buffer.write('        <d:creationdate>${obj.lastModified?.toIso8601String() ?? DateTime.now().toIso8601String()}</d:creationdate>\n');
      buffer.write('        <d:getlastmodified>${obj.lastModified?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String()}</d:getlastmodified>\n');
      if (obj.type == ObjectType.folder) {
        buffer.write('        <d:resourcetype><d:collection/></d:resourcetype>\n');
      } else {
        buffer.write('        <d:resourcetype/>\n');
        buffer.write('        <d:getcontentlength>${obj.size}</d:getcontentlength>\n');
      }
      buffer.write('      </d:prop>\n');
      buffer.write('      <d:status>HTTP/1.1 200 OK</d:status>\n');
      buffer.write('    </d:propstat>\n');
      buffer.write('  </d:response>\n');
    }

    buffer.write('</d:multistatus>\n');
    return buffer.toString();
  }

  /// 处理GET请求 - 下载文件
  Future<WebdavResponse> _handleGet(String path) async {
    final relativePath = _getRelativePath(path);
    if (relativePath.isEmpty || relativePath.endsWith('/')) {
      return WebdavResponse.notFound();
    }

    final api = config.factory.createApi(config.platform, credential: config.credential);
    if (api == null) {
      return WebdavResponse.serverError(body: 'Failed to create API');
    }

    try {
      // 创建临时文件用于下载
      final tempDir = await Directory.systemTemp.createTemp('webdav_download_');
      final tempFile = File('${tempDir.path}/${Uri.encodeComponent(relativePath)}');
      tempFile.parent.createSync(recursive: true);

      final result = await api.downloadObject(
        bucketName: config.bucketName,
        region: config.region,
        objectKey: relativePath,
        outputFile: tempFile,
      );

      if (!result.success) {
        return WebdavResponse.notFound(bodyBytes: utf8.encode(result.errorMessage ?? 'File not found'));
      }

      // 读取文件内容并返回
      final data = await tempFile.readAsBytes();
      return WebdavResponse.ok(
        bodyBytes: data,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': data.length.toString(),
        },
      );
    } catch (e) {
      return WebdavResponse.notFound(bodyBytes: utf8.encode(e.toString()));
    }
  }

  /// 处理HEAD请求 - 检查文件是否存在
  Future<WebdavResponse> _handleHead(String path) async {
    final relativePath = _getRelativePath(path);
    if (relativePath.isEmpty) {
      return WebdavResponse.notFound();
    }

    final api = config.factory.createApi(config.platform, credential: config.credential);
    if (api == null) {
      return WebdavResponse.serverError(body: 'Failed to create API');
    }

    try {
      final result = await api.listObjects(
        bucketName: config.bucketName,
        region: config.region,
        prefix: relativePath,
        maxKeys: 1,
      );

      if (result.success && (result.data?.objects ?? []).isNotEmpty) {
        return WebdavResponse.ok(headers: {'Content-Length': '0'});
      }
      return WebdavResponse.notFound();
    } catch (e) {
      return WebdavResponse.notFound();
    }
  }

  /// 处理PUT请求 - 上传文件
  Future<WebdavResponse> _handlePut(HttpRequest request, String path) async {
    final relativePath = _getRelativePath(path);
    if (relativePath.isEmpty || relativePath.endsWith('/')) {
      return WebdavResponse.conflict(body: 'Invalid path');
    }

    final api = config.factory.createApi(config.platform, credential: config.credential);
    if (api == null) {
      return WebdavResponse.serverError(body: 'Failed to create API');
    }

    try {
      final bytes = await request.fold<List<int>>([], (list, chunk) => list..addAll(chunk));
      final result = await api.uploadObject(
        bucketName: config.bucketName,
        region: config.region,
        objectKey: relativePath,
        data: bytes,
      );

      if (result.success) {
        return WebdavResponse.created();
      }
      return WebdavResponse.serverError(bodyBytes: utf8.encode(result.errorMessage ?? 'Upload failed'));
    } catch (e) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode(e.toString()));
    }
  }

  /// 处理MKCOL请求 - 创建目录
  Future<WebdavResponse> _handleMkcol(String path) async {
    final relativePath = _getRelativePath(path);
    if (relativePath.isEmpty) {
      return WebdavResponse.conflict(bodyBytes: utf8.encode('Invalid path'));
    }

    final api = config.factory.createApi(config.platform, credential: config.credential);
    if (api == null) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode('Failed to create API'));
    }

    try {
      final result = await api.createFolder(
        bucketName: config.bucketName,
        region: config.region,
        folderName: relativePath.endsWith('/') ? relativePath.substring(0, relativePath.length - 1) : relativePath,
      );

      if (result.success) {
        return WebdavResponse.created();
      }
      return WebdavResponse.serverError(bodyBytes: utf8.encode(result.errorMessage ?? 'Failed to create folder'));
    } catch (e) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode(e.toString()));
    }
  }

  /// 处理DELETE请求 - 删除文件/目录
  Future<WebdavResponse> _handleDelete(String path) async {
    final relativePath = _getRelativePath(path);
    if (relativePath.isEmpty) {
      return WebdavResponse.conflict(bodyBytes: utf8.encode('Cannot delete root'));
    }

    final api = config.factory.createApi(config.platform, credential: config.credential);
    if (api == null) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode('Failed to create API'));
    }

    try {
      // 先检查是否是目录
      final checkPath = relativePath.endsWith('/') ? relativePath : '$relativePath/';
      final listResult = await api.listObjects(
        bucketName: config.bucketName,
        region: config.region,
        prefix: checkPath,
        delimiter: '/',
        maxKeys: 1,
      );

      final isFolder = listResult.success &&
          (listResult.data?.objects ?? []).isNotEmpty &&
          listResult.data!.objects.first.type == ObjectType.folder;

      if (isFolder) {
        final result = await api.deleteFolder(
          bucketName: config.bucketName,
          region: config.region,
          folderKey: checkPath,
        );
        if (!result.success) {
          return WebdavResponse.serverError(bodyBytes: utf8.encode(result.errorMessage ?? 'Failed to delete folder'));
        }
      } else {
        final result = await api.deleteObject(
          bucketName: config.bucketName,
          region: config.region,
          objectKey: relativePath,
        );
        if (!result.success) {
          return WebdavResponse.serverError(bodyBytes: utf8.encode(result.errorMessage ?? 'Failed to delete file'));
        }
      }

      return WebdavResponse.noContent();
    } catch (e) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode(e.toString()));
    }
  }

  /// 处理COPY请求 - 复制文件
  Future<WebdavResponse> _handleCopy(HttpRequest request, String path) async {
    final destination = request.headers['destination']?.first;
    if (destination == null) {
      return WebdavResponse.badRequest();
    }

    final relativePath = _getRelativePath(path);
    final destPath = _getRelativePath(Uri.parse(destination).path);

    if (relativePath.isEmpty || destPath.isEmpty) {
      return WebdavResponse.conflict();
    }

    final api = config.factory.createApi(config.platform, credential: config.credential);
    if (api == null) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode('Failed to create API'));
    }

    try {
      final result = await api.copyObject(
        bucketName: config.bucketName,
        region: config.region,
        sourceKey: relativePath,
        targetKey: destPath,
      );

      if (result.success) {
        return WebdavResponse.created();
      }
      return WebdavResponse.serverError(bodyBytes: utf8.encode(result.errorMessage ?? 'Copy failed'));
    } catch (e) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode(e.toString()));
    }
  }

  /// 处理MOVE请求 - 移动文件
  Future<WebdavResponse> _handleMove(HttpRequest request, String path) async {
    final destination = request.headers['destination']?.first;
    if (destination == null) {
      return WebdavResponse.badRequest();
    }

    final relativePath = _getRelativePath(path);
    final destPath = _getRelativePath(Uri.parse(destination).path);

    if (relativePath.isEmpty || destPath.isEmpty) {
      return WebdavResponse.conflict();
    }

    // 移动操作 = 复制 + 删除
    final api = config.factory.createApi(config.platform, credential: config.credential);
    if (api == null) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode('Failed to create API'));
    }

    try {
      // 先复制
      final copyResult = await api.copyObject(
        bucketName: config.bucketName,
        region: config.region,
        sourceKey: relativePath,
        targetKey: destPath,
      );

      if (!copyResult.success) {
        return WebdavResponse.serverError(bodyBytes: utf8.encode(copyResult.errorMessage ?? 'Move failed'));
      }

      // 再删除
      final deleteResult = await api.deleteObject(
        bucketName: config.bucketName,
        region: config.region,
        objectKey: relativePath,
      );

      if (!deleteResult.success) {
        logUi('WebDAV: Copy succeeded but delete failed: ${deleteResult.errorMessage}');
      }

      return WebdavResponse.created();
    } catch (e) {
      return WebdavResponse.serverError(bodyBytes: utf8.encode(e.toString()));
    }
  }

  /// 获取相对路径
  String _getRelativePath(String path) {
    if (path == '/' || path.isEmpty) {
      return '';
    }
    // 移除前导斜杠
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    // URL解码
    return Uri.decodeComponent(normalizedPath);
  }
}

/// WebDAV服务器
class WebdavServer {
  final WebdavServerConfig config;
  HttpServer? _server;
  WebdavProtocolHandler? _handler;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int? get port => _server?.port;

  WebdavServer({required this.config});

  /// 启动服务器
  Future<void> start() async {
    if (_isRunning) {
      logUi('WebDAV: Server is already running');
      return;
    }

    _handler = WebdavProtocolHandler(config: config);

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, config.port);
      _isRunning = true;

      logUi('WebDAV: Server started on port ${config.port}');

      // 在后台处理请求，不要阻塞 start() 方法
      _server!.listen(
        _handleRequest,
        onError: (error) {
          logError('WebDAV: Server listen error: $error');
        },
        onDone: () {
          logUi('WebDAV: Server connection closed');
        },
      );
    } catch (e) {
      logError('WebDAV: Failed to start server: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// 处理请求
  void _handleRequest(HttpRequest request) {
    final handler = _handler;
    if (handler == null) {
      request.response.statusCode = 500;
      request.response.write('Server not initialized');
      request.response.close();
      return;
    }

    handler.handleRequest(request).then((response) {
      request.response.statusCode = response.statusCode;
      response.headers.forEach((key, value) {
        request.response.headers.set(key, value);
      });
      request.response.add(response.bodyBytes);
      request.response.close();
    }).catchError((error) {
      logError('WebDAV: Error handling request: $error');
      request.response.statusCode = 500;
      request.response.write('Internal server error');
      request.response.close();
    });
  }

  /// 停止服务器
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    await _server?.close();
    _server = null;
    _handler = null;
    _isRunning = false;

    logUi('WebDAV: Server stopped');
  }
}
