import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bucket.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
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
    logUi('_refreshCurrentPlatform called');
    final storage = Provider.of<StorageService>(context, listen: false);
    logUi('_refreshCurrentPlatform: getting last platform...');
    final lastPlatform = await storage.getLastPlatform();
    logUi('_refreshCurrentPlatform: lastPlatform = $lastPlatform');
    if (lastPlatform == null) {
      logUi('_refreshCurrentPlatform: no last platform, returning');
      return;
    }

    // 使用 Future.delayed 避免在异步回调中直接 setState
    // 这样可以确保 UI 更新在下一个事件循环中执行
    // 同时检查 mounted 状态
    logUi('_refreshCurrentPlatform: checking mounted...');
    if (!mounted) {
      logUi('_refreshCurrentPlatform: not mounted, returning');
      return;
    }
    await Future.delayed(Duration.zero);

    if (!mounted) {
      logUi('_refreshCurrentPlatform: not mounted after delay, returning');
      return;
    }
    setState(() {
      _currentPlatform = lastPlatform;
      _buckets = []; // 清空旧数据
    });
    logUi('Refreshed platform: ${lastPlatform.displayName}');

    // 再次检查 mounted 状态后再调用 _loadBuckets
    if (!mounted) {
      logUi('_refreshCurrentPlatform: not mounted before loadBuckets, returning');
      return;
    }
    await _loadBuckets();
  }

  Future<void> _loadBuckets() async {
    if (_currentPlatform == null) return;
    logUi('Loading buckets for platform: ${_currentPlatform!.displayName}');

    // 先获取凭证
    final storage = Provider.of<StorageService>(context, listen: false);
    final credential = await storage.getCredential(_currentPlatform!);

    if (credential == null) {
      logError(
        'No credential found for platform: ${_currentPlatform!.displayName}',
      );
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
        actions: [
          if (_currentPlatform != null) _buildViewModeToggle(),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
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
                  logUi('User tapped: 去选择平台');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlatformSelectionScreen(),
                    ),
                  );
                },
                child: Text('去选择平台'),
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
          child: Container(
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
}
