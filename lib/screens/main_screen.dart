import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bucket.dart';
import '../models/platform_type.dart';
import '../models/storage_class.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';
import 'platform_selection_screen.dart';
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
            _showStorageClassDialog(bucket);
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
            _showStorageClassDialog(bucket);
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

  /// 显示存储类型选择对话框
  void _showStorageClassDialog(Bucket bucket) {
    final storage = Provider.of<StorageService>(context, listen: false);

    showModalBottomSheet(
      context: context,
      builder: (context) => FutureBuilder<StorageClass?>(
        future: storage.getBucketStorageClass(_currentPlatform!, bucket.name),
        builder: (context, snapshot) {
          final currentClass = snapshot.data;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '设置存储类型',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '仅对后续上传对象有效',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Text(
                  '存储桶: ${bucket.name}',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 8),
                if (snapshot.connectionState == ConnectionState.waiting)
                  CircularProgressIndicator()
                else
                  ..._buildStorageClassOptions(
                    context,
                    bucket,
                    currentClass ?? StorageClass.standard,
                    storage,
                  ),
                SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建存储类型选项列表
  List<Widget> _buildStorageClassOptions(
    BuildContext context,
    Bucket bucket,
    StorageClass currentClass,
    StorageService storage,
  ) {
    final isTencent = _currentPlatform!.value == 'tencent';

    // 根据平台过滤可用的存储类型
    final availableClasses = isTencent
        ? [
            StorageClass.standard,
            StorageClass.standardIa,
            StorageClass.archive,
            StorageClass.deepArchive,
            StorageClass.intelligentTiering,
          ]
        : [
            StorageClass.standard,
            StorageClass.standardIa,
            StorageClass.archive,
            StorageClass.coldArchive,
            StorageClass.deepColdArchive,
          ];

    return availableClasses.map((sc) {
      final isSelected = sc == currentClass;
      return ListTile(
        leading: Icon(
          isSelected ? Icons.check_circle : Icons.circle_outlined,
          color: isSelected ? Colors.blue : Colors.grey,
        ),
        title: Text(sc.displayName),
        subtitle: isTencent
            ? Text(_getTencentStorageDesc(sc))
            : Text(_getAliyunStorageDesc(sc)),
        selected: isSelected,
        selectedTileColor: Colors.blue.withValues(alpha: 0.1),
        onTap: () async {
          if (isSelected) {
            Navigator.pop(context);
            return;
          }
          await storage.setBucketStorageClass(
            _currentPlatform!,
            bucket.name,
            sc,
          );
          if (!mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已设置为 ${sc.displayName}')),
          );
          setState(() {});
        },
      );
    }).toList()
      ..add(
        ListTile(
          leading: Icon(Icons.delete_outline, color: Colors.red),
          title: Text('清除设置'),
          onTap: () async {
            await storage.clearBucketStorageClass(_currentPlatform!, bucket.name);
            if (!mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已清除存储类型设置')),
            );
            setState(() {});
          },
        ),
      );
  }

  /// 获取腾讯云存储类型描述
  String _getTencentStorageDesc(StorageClass sc) {
    switch (sc) {
      case StorageClass.standard:
        return '默认类型，适合频繁访问的数据';
      case StorageClass.standardIa:
        return '低频存储，适合较少访问的数据';
      case StorageClass.archive:
        return '归档存储，适合长期保存的数据';
      case StorageClass.deepArchive:
        return '深度归档存储，适合极少访问的数据';
      case StorageClass.intelligentTiering:
        return '智能分层，自动降冷以节省成本';
      default:
        return '';
    }
  }

  /// 获取阿里云存储类型描述
  String _getAliyunStorageDesc(StorageClass sc) {
    switch (sc) {
      case StorageClass.standard:
        return '默认类型，适合频繁访问的数据';
      case StorageClass.standardIa:
        return '低频存储，适合较少访问的数据';
      case StorageClass.archive:
        return '归档存储，适合长期保存的数据';
      case StorageClass.coldArchive:
        return '冷归档存储，适合超长期保存';
      case StorageClass.deepColdArchive:
        return '深度冷归档存储，适合合规存档';
      default:
        return '';
    }
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
