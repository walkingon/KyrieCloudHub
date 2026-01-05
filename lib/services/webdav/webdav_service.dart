import 'dart:async';
import '../../models/bucket.dart';
import '../../models/platform_type.dart';
import '../../models/platform_credential.dart';
import '../storage_service.dart';
import '../cloud_platform_factory.dart';
import 'webdav_server.dart';

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

    // 如果服务器已存在，先停止
    await stopServer(serverKey);

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
      await server.start();

      // 保存配置
      await _storage.saveWebdavConfig(bucket.name, true, serverPort);

      _servers[serverKey] = server;

      return true;
    } catch (e) {
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
    return _servers[serverKey]?.isRunning ?? false;
  }

  /// 获取服务器端口
  int? getServerPort(String bucketName, PlatformType platform) {
    final serverKey = _getServerKey(bucketName, platform);
    return _servers[serverKey]?.port;
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
