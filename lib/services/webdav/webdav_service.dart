import 'dart:async';
import '../../models/bucket.dart';
import '../../models/platform_type.dart';
import '../../models/platform_credential.dart';
import '../storage_service.dart';
import '../cloud_platform_factory.dart';
import 'webdav_server.dart';
import '../../utils/logger.dart';

/// WebDAV服务管理器
class WebdavService {
  static final WebdavService _instance = WebdavService._internal();
  factory WebdavService() => _instance;
  WebdavService._internal();

  final Map<String, WebdavServer> _servers = {};
  final StorageService _storage = StorageService();
  final CloudPlatformFactory _factory = CloudPlatformFactory();

  /// 启动存储桶的WebDAV服务
  Future<bool> startServer({
    required Bucket bucket,
    required PlatformType platform,
    required PlatformCredential credential,
    int? port,
  }) async {
    final serverPort = port ?? 8080;
    final serverKey = _getServerKey(bucket.name, platform);

    logUi('WebDAV: startServer called - bucket: ${bucket.name}, platform: ${platform.value}, port: $serverPort, key: $serverKey');

    // 如果服务器已存在，先停止
    await stopServer(serverKey);

    logUi('WebDAV: Existing server stopped, creating new server');

    final config = WebdavServerConfig(
      bucketName: bucket.name,
      region: bucket.region,
      port: serverPort,
      platform: platform,
      credential: credential,
      factory: _factory,
    );

    final server = WebdavServer(config: config);

    try {
      logUi('WebDAV: Starting server...');
      await server.start();
      logUi('WebDAV: Server started successfully, isRunning: ${server.isRunning}');

      // 保存配置（异步，不阻塞返回）
      _storage.saveWebdavConfig(bucket.name, true, serverPort).then((_) {
        logUi('WebDAV: Config saved');
      }).catchError((e) {
        logError('WebDAV: Failed to save config: $e');
      });

      _servers[serverKey] = server;
      logUi('WebDAV: Server registered, _servers contains: ${_servers.keys.join(', ')}, server.isRunning: ${server.isRunning}');

      return true;
    } catch (e, stack) {
      logError('WebDAV: Failed to start server: $e');
      logError('WebDAV: Stack trace: $stack');
      return false;
    }
  }

  /// 停止WebDAV服务
  Future<void> stopServerByBucket(String bucketName, PlatformType platform) async {
    final serverKey = _getServerKey(bucketName, platform);
    await stopServer(serverKey);
  }

  /// 停止指定服务器
  Future<void> stopServer(String serverKey) async {
    final server = _servers.remove(serverKey);
    if (server != null) {
      await server.stop();
    }
  }

  /// 停止所有WebDAV服务
  Future<void> stopAllServers() async {
    for (final server in _servers.values) {
      await server.stop();
    }
    _servers.clear();
  }

  /// 检查存储桶的WebDAV服务是否正在运行
  bool isServerRunning(String bucketName, PlatformType platform) {
    final serverKey = _getServerKey(bucketName, platform);
    final server = _servers[serverKey];
    final isRunning = server?.isRunning ?? false;
    logUi('WebDAV: isServerRunning - bucket: $bucketName, key: $serverKey, server exists: ${server != null}, isRunning: $isRunning, allKeys: ${_servers.keys.join(', ')}');
    return isRunning;
  }

  /// 获取服务器端口
  int? getServerPort(String bucketName, PlatformType platform) {
    final serverKey = _getServerKey(bucketName, platform);
    final port = _servers[serverKey]?.port;
    logUi('WebDAV: getServerPort - bucket: $bucketName, key: $serverKey, port: $port');
    return port;
  }

  /// 获取服务器URL
  String? getServerUrl(String bucketName, PlatformType platform) {
    final port = getServerPort(bucketName, platform);
    if (port == null) return null;
    return 'http://localhost:$port';
  }

  /// 获取服务器Key
  String _getServerKey(String bucketName, PlatformType platform) {
    return '${platform.value}_$bucketName';
  }

  /// 获取所有正在运行的服务器信息
  List<Map<String, dynamic>> getRunningServersInfo() {
    return _servers.entries.map((entry) {
      final server = entry.value;
      return {
        'key': entry.key,
        'port': server.port,
        'running': server.isRunning,
      };
    }).toList();
  }
}
