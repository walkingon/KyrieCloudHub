import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/bucket.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
import '../services/webdav/webdav_server.dart';
import '../services/webdav/webdav_service.dart';
import '../utils/logger.dart';
import 'platform_selection_screen.dart';
import 'transfer_queue_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'bucket_objects_screen.dart';

// ignore_for_file: library_private_types_in_public_api

/// 视图模式枚举
enum ViewMode {
  list,
  grid,
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  PlatformType? _currentPlatform;
  List<Bucket> _buckets = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // 视图模式
  ViewMode _viewMode = ViewMode.list;

  @override
  void initState() {
    super.initState();
    logUi('MainScreen initialized');
    _loadLastPlatform();
  }

  Future<void> _loadLastPlatform() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final lastPlatform = await storage.getLastPlatform();
    if (lastPlatform != null) {
      setState(() {
        _currentPlatform = lastPlatform;
      });
      logUi('Auto-loaded last platform: ${lastPlatform.displayName}');
      _loadBuckets();
    } else {
      logUi('No last platform found, showing empty state');
    }
  }

  /// 刷新当前平台数据（从平台选择界面返回时调用）
  Future<void> _refreshCurrentPlatform() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final lastPlatform = await storage.getLastPlatform();
    if (lastPlatform == null) return;

    // 等待当前帧完成
    await Future.delayed(Duration(milliseconds: 50));

    if (!mounted) return;

    setState(() {
      _currentPlatform = lastPlatform;
      _buckets = [];
    });

    await _loadBuckets();
  }

  Future<void> _loadBuckets() async {
    if (_currentPlatform == null) return;
    logUi('Loading buckets for platform: ${_currentPlatform!.displayName}');

    // 先获取凭证
    final storage = Provider.of<StorageService>(context, listen: false);
    final credential = await storage.getCredential(_currentPlatform!);

    if (credential == null) {
      logUi('No credential found for platform: ${_currentPlatform!.displayName}, showing platform selection');
      setState(() {
        _currentPlatform = null;
        _buckets = [];
      });
      return;
    }

    logUi('Credential found for platform: ${_currentPlatform!.displayName}');

    // ignore: use_build_context_synchronously
    final factory = Provider.of<CloudPlatformFactory>(context, listen: false);
    final api = factory.createApi(_currentPlatform!, credential: credential);

    if (api == null) {
      logError(
        'Failed to create API for platform: ${_currentPlatform!.displayName}',
      );
      return;
    }

    final result = await api.listBuckets();

    // 使用 Future.delayed 确保 setState 在下一个事件循环执行
    if (!mounted) return;
    await Future.delayed(Duration.zero);

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _buckets = result.data ?? [];
      });
      logUi('Loaded ${_buckets.length} buckets');
    } else {
      logError('Failed to load buckets: ${result.errorMessage}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_currentPlatform?.displayName ?? ''),
        centerTitle: true,
        backgroundColor: _currentPlatform?.color ?? Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_currentPlatform != null) _buildViewModeToggle(),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'KyrieCloudHub',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz),
              title: Text('平台切换'),
              onTap: () {
                logUi('User tapped: 平台切换');
                _scaffoldKey.currentState?.closeDrawer();
                // 使用 push 而不是 pushReplacement，保持 MainScreen 在栈中
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlatformSelectionScreen(),
                  ),
                ).then((_) {
                  // 从平台选择界面返回时刷新数据
                  logUi('PlatformSelectionScreen returned, calling _refreshCurrentPlatform');
                  _refreshCurrentPlatform();
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.queue),
              title: Text('传输队列'),
              onTap: () {
                logUi('User tapped: 传输队列');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TransferQueueScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('设置'),
              onTap: () {
                logUi('User tapped: 设置');
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.info),
              title: Text('关于'),
              onTap: () {
                logUi('User tapped: 关于');
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AboutScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: _currentPlatform == null
          ? Center(
              child: ElevatedButton(
                onPressed: () {
                  logUi('User tapped: 去登录');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlatformSelectionScreen(),
                    ),
                  ).then((_) {
                    // 从平台选择界面返回时刷新数据
                    _refreshCurrentPlatform();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                  shape: StadiumBorder(),
                  elevation: 4,
                ),
                child: Text('去登录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            )
          : _buckets.isEmpty
              ? Center(child: Text('暂无存储桶'))
              : _viewMode == ViewMode.grid
                  ? _buildGridView()
                  : _buildListView(),
    );
  }

  /// 构建视图模式切换按钮
  Widget _buildViewModeToggle() {
    return IconButton(
      icon: Icon(_viewMode == ViewMode.list ? Icons.grid_view : Icons.view_list),
      onPressed: _toggleViewMode,
      tooltip: _viewMode == ViewMode.list ? '网格视图' : '列表视图',
    );
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
    });
    logUi('View mode changed to: ${_viewMode.name}');
  }

  /// 构建列表视图
  Widget _buildListView() {
    return ListView.builder(
      itemCount: _buckets.length,
      itemBuilder: (context, index) {
        final bucket = _buckets[index];
        return ListTile(
          leading: Icon(Icons.storage),
          title: Text(bucket.name),
          subtitle: Text(bucket.region),
          trailing: _buildWebdavIndicator(bucket),
          onTap: () {
            logUi('User tapped bucket: ${bucket.name}');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BucketObjectsScreen(
                  bucket: bucket,
                  platform: _currentPlatform!,
                ),
              ),
            );
          },
          onLongPress: () {
            logUi('User long pressed bucket: ${bucket.name}');
            _showBucketOptionsMenu(bucket);
          },
        );
      },
    );
  }

  /// 构建网格视图
  Widget _buildGridView() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getCrossAxisCount(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.2,
      ),
      padding: EdgeInsets.all(16),
      itemCount: _buckets.length,
      itemBuilder: (context, index) {
        final bucket = _buckets[index];
        return GestureDetector(
          onTap: () {
            logUi('User tapped bucket: ${bucket.name}');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BucketObjectsScreen(
                  bucket: bucket,
                  platform: _currentPlatform!,
                ),
              ),
            );
          },
          onLongPress: () {
            logUi('User long pressed bucket: ${bucket.name}');
            _showBucketOptionsMenu(bucket);
          },
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storage,
                      size: 48,
                      color: Colors.blue,
                    ),
                    SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        bucket.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      bucket.region,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: _buildWebdavIndicator(bucket),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 根据屏幕宽度获取网格列数
  int _getCrossAxisCount() {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 900) return 5;
    if (width > 600) return 4;
    if (width > 400) return 3;
    return 2;
  }

  /// 构建WebDAV状态指示器
  Widget _buildWebdavIndicator(Bucket bucket) {
    final webdavService = WebdavService();
    final serverKey = '${_currentPlatform?.value}_${bucket.name}';
    final isRunning = webdavService.isServerRunning(bucket.name, _currentPlatform!);
    final port = webdavService.getServerPort(bucket.name, _currentPlatform!);

    logUi('WebDAV indicator - bucket: ${bucket.name}, key: $serverKey, isRunning: $isRunning, port: $port, servers: ${webdavService.getRunningServersInfo()}');

    if (isRunning) {
      return Icon(
        Icons.cloud_done,
        color: Colors.green,
        size: 20,
      );
    }
    return SizedBox.shrink();
  }

  /// 显示存储桶操作菜单
  void _showBucketOptionsMenu(Bucket bucket) {
    if (_currentPlatform == null) return;
    final webdavService = WebdavService();
    final isRunning = webdavService.isServerRunning(bucket.name, _currentPlatform!);
    final currentPort = webdavService.getServerPort(bucket.name, _currentPlatform!);

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(isRunning ? Icons.stop : Icons.play_arrow),
            title: Text(isRunning ? '关闭WebDAV服务' : '开启WebDAV服务'),
            subtitle: isRunning ? Text('端口: $currentPort') : null,
            onTap: () {
              Navigator.pop(context);
              _toggleWebdavService(bucket, isRunning);
            },
          ),
          if (isRunning) ...[
            ListTile(
              leading: Icon(Icons.content_copy),
              title: Text('复制WebDAV地址'),
              subtitle: Text('http://localhost:$currentPort'),
              onTap: () {
                Navigator.pop(context);
                _copyWebdavUrl(bucket, currentPort ?? 8080);
              },
            ),
          ],
          SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 切换WebDAV服务状态
  Future<void> _toggleWebdavService(Bucket bucket, bool currentlyRunning) async {
    if (_currentPlatform == null) return;

    final storage = Provider.of<StorageService>(context, listen: false);
    final credential = await storage.getCredential(_currentPlatform!);

    if (credential == null) {
      _showErrorDialog('无法获取凭证，请重新登录');
      return;
    }

    final webdavService = WebdavService();

    if (currentlyRunning) {
      await webdavService.stopServerByBucket(bucket.name, _currentPlatform!);
      logUi('WebDAV: Stopped server for bucket: ${bucket.name}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WebDAV服务已关闭')),
        );
      }
    } else {
      // 查找可用端口
      int port = 8080;
      while (webdavService.getServerPort(bucket.name, _currentPlatform!) == null &&
          port < 8200) {
        try {
          final testServer = WebdavServer(
            config: WebdavServerConfig(
              bucketName: bucket.name,
              region: bucket.region,
              port: port,
              platform: _currentPlatform!,
              credential: credential,
              factory: CloudPlatformFactory(),
            ),
          );
          await testServer.start();
          await testServer.stop();
          break;
        } catch (e) {
          port++;
        }
      }
      logUi('WebDAV: Found available port: $port');

      final success = await webdavService.startServer(
        bucket: bucket,
        platform: _currentPlatform!,
        credential: credential,
        port: port,
      );

      logUi('WebDAV: startServer result: $success, isRunning: ${webdavService.isServerRunning(bucket.name, _currentPlatform!)}');

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('WebDAV服务已启动\n访问地址: http://localhost:$port')),
          );
        } else {
          _showErrorDialog('启动WebDAV服务失败');
        }
      }
    }

    // 强制刷新界面
    if (mounted) {
      setState(() {});
    }
  }

  /// 复制WebDAV URL
  void _copyWebdavUrl(Bucket bucket, int port) async {
    final url = 'http://localhost:$port';
    await Clipboard.setData(ClipboardData(text: url));
    _showMessage('地址已复制: $url');
  }

  /// 显示错误对话框
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示消息提示
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
