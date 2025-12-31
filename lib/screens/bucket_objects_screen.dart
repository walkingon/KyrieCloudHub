import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/bucket.dart';
import '../models/object_file.dart';
import '../models/platform_type.dart';
import '../services/api/cloud_platform_api.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';

// ignore_for_file: library_private_types_in_public_api

/// 视图模式枚举
enum ViewMode {
  list,
  grid,
}

/// 加载状态
enum LoadingState {
  idle,
  loading,
  success,
  error,
}

class BucketObjectsScreen extends StatefulWidget {
  final Bucket bucket;
  final PlatformType platform;

  const BucketObjectsScreen({
    super.key,
    required this.bucket,
    required this.platform,
  });

  @override
  _BucketObjectsScreenState createState() => _BucketObjectsScreenState();
}

class _BucketObjectsScreenState extends State<BucketObjectsScreen> {
  List<ObjectFile> _objects = [];
  LoadingState _loadingState = LoadingState.idle;
  String _errorMessage = '';
  late final StorageService _storage;
  late final CloudPlatformFactory _factory;

  // 视图模式
  ViewMode _viewMode = ViewMode.list;

  // 多选模式相关
  bool _isSelectionMode = false;
  final Set<String> _selectedObjects = {};

  // 当前路径
  String _currentPrefix = '';

  // 分页相关
  static const int _pageSize = 10;
  int _currentPage = 1;
  bool _hasMore = false;
  String? _nextMarker;
  bool _isLoadingMore = false;

  List<ObjectFile> get _selectedFileList =>
      _objects.where((obj) => _selectedObjects.contains(obj.key)).toList();

  // 当前路径分段（用于路径导航）
  List<String> get _pathSegments {
    if (_currentPrefix.isEmpty) return [];
    final parts = _currentPrefix.split('/').where((e) => e.isNotEmpty).toList();
    return parts;
  }

  @override
  void initState() {
    super.initState();
    logUi('BucketObjectsScreen initialized for bucket: ${widget.bucket.name}');
    _storage = Provider.of<StorageService>(context, listen: false);
    _factory = Provider.of<CloudPlatformFactory>(context, listen: false);
    _loadObjects(refresh: true);
  }

  Future<void> _loadObjects({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loadingState = LoadingState.loading;
        _errorMessage = '';
        if (_currentPage == 1) {
          _objects = [];
        }
      });
    }

    logUi('Loading objects for bucket: ${widget.bucket.name}, prefix: "$_currentPrefix", page: $_currentPage');

    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      _setError('未找到登录凭证');
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      _setError('API创建失败');
      return;
    }

    try {
      final result = await api.listObjects(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        prefix: _currentPrefix,
        delimiter: '/',
        maxKeys: _pageSize,
        marker: _currentPage == 1 ? null : _nextMarker,
      );

      if (!mounted) return;

      if (result.success && result.data != null) {
        logUi('Before setState: page=$_currentPage, objects=${_objects.length}');
        setState(() {
          // 每次加载都替换数据（传统分页模式）
          _objects = result.data!.objects;
          _hasMore = result.data!.isTruncated;
          _nextMarker = result.data!.nextMarker;
          _loadingState = _objects.isEmpty ? LoadingState.success : LoadingState.success;
          _errorMessage = '';
          _isLoadingMore = false;
        });
        logUi('After setState: page=$_currentPage, objects=${_objects.length}, hasMore=$_hasMore');
        logUi('Loaded ${_objects.length} objects, hasMore: $_hasMore, page: $_currentPage');
      } else {
        _setError(result.errorMessage ?? '加载失败');
        if (mounted) {
          setState(() {
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      _setError('加载失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _setError(String message) {
    setState(() {
      _loadingState = LoadingState.error;
      _errorMessage = message;
    });
    logError('Load objects error: $message');
  }

  /// 加载下一页
  void _loadNextPage() {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    _loadObjects();
  }

  /// 加载上一页
  void _loadPreviousPage() {
    if (_isLoadingMore || _currentPage <= 1) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage--;
    });
    _loadObjects();
  }

  /// 刷新当前页
  Future<void> _refresh() async {
    _currentPage = 1;
    _nextMarker = null;
    _hasMore = false;
    await _loadObjects(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(),
        backgroundColor: widget.platform.color,
        foregroundColor: Colors.white,
        actions: [
          if (!_isSelectionMode) _buildViewModeToggle(),
          ..._buildSelectionActions(),
        ],
        leading: _isSelectionMode
            ? IconButton(
                icon: Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
                tooltip: '返回',
              ),
      ),
      body: _buildBody(),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton(
              tooltip: '添加',
              onPressed: _showAddOptions,
              child: Icon(Icons.add),
            ),
    );
  }

  /// 构建标题（包含路径导航）
  Widget _buildTitle() {
    if (_isSelectionMode) {
      return Text('已选择 ${_selectedObjects.length} 项');
    }

    if (_pathSegments.isEmpty) {
      return Text(widget.bucket.name);
    }

    return SizedBox(
      width: 200,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _pathSegments.last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建路径导航栏
  Widget _buildPathNavigation() {
    if (_pathSegments.isEmpty) {
      return Container();
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          // 返回根目录按钮
          TextButton.icon(
            icon: Icon(Icons.home, size: 18),
            label: Text('根目录'),
            onPressed: _currentPrefix.isEmpty ? null : _navigateToRoot,
          ),
          Text(' / '),
          // 路径分段
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _buildPathChips(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPathChips() {
    final chips = <Widget>[];
    final segments = _pathSegments;

    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        chips.add(Text(' / '));
      }

      final isLast = i == segments.length - 1;
      // 构建到当前 segment 的前缀路径：segments[0..i] + '/'
      final prefix = '${segments.sublist(0, i + 1).join('/')}/';

      chips.add(
        ActionChip(
          label: Text(
            segments[i],
            style: TextStyle(
              color: isLast ? Colors.blue : Colors.black87,
              fontWeight: isLast ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          onPressed: isLast ? null : () => _navigateToPrefix(prefix),
          avatar: isLast ? null : Icon(Icons.folder, size: 16),
        ),
      );
    }

    return chips;
  }

  void _navigateToRoot() {
    if (_currentPrefix.isNotEmpty) {
      setState(() {
        _currentPrefix = '';
        _currentPage = 1;
      });
      _refresh();
    }
  }

  void _navigateToPrefix(String prefix) {
    if (prefix != _currentPrefix) {
      setState(() {
        _currentPrefix = prefix;
        _currentPage = 1;
      });
      _refresh();
    }
  }

  /// 显示添加选项（上传文件/新建文件夹）
  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.file_upload),
            title: Text('上传文件'),
            onTap: () {
              Navigator.pop(context);
              _uploadFiles();
            },
          ),
          ListTile(
            leading: Icon(Icons.create_new_folder),
            title: Text('新建文件夹'),
            onTap: () {
              Navigator.pop(context);
              _showCreateFolderDialog();
            },
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 显示新建文件夹对话框
  void _showCreateFolderDialog() {
    final TextEditingController controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('新建文件夹'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '文件夹名称',
                    hintText: '请输入文件夹名称',
                    errorText: errorText,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入文件夹名称';
                    }
                    if (value.contains('/') || value.contains('\\')) {
                      return '名称不能包含 / 或 \\';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final folderName = controller.text.trim();
                if (_objects.any((obj) => obj.name == folderName && obj.type == ObjectType.folder)) {
                  setState(() {
                    errorText = '文件夹已存在';
                  });
                  return;
                }

                Navigator.pop(context);
                _createFolder(folderName);
              },
              child: Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  /// 创建文件夹
  Future<void> _createFolder(String folderName) async {
    logUi('Creating folder: $folderName in prefix: "$_currentPrefix"');

    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      _showErrorSnackBar('未找到登录凭证');
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      _showErrorSnackBar('API创建失败');
      return;
    }

    setState(() {
      _loadingState = LoadingState.loading;
    });

    final result = await api.createFolder(
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      folderName: folderName,
      prefix: _currentPrefix,
    );

    if (!mounted) return;

    if (result.success) {
      logUi('Folder created successfully: $folderName');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件夹 "$folderName" 创建成功')),
      );
      _refresh();
    } else {
      _showErrorSnackBar(result.errorMessage ?? '创建失败');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // 路径导航
        _buildPathNavigation(),
        // 加载状态/错误提示
        _buildStatusWidget(),
        // 文件列表
        Expanded(
          child: _buildContent(),
        ),
        // 分页控制器
        _buildPaginationControls(),
      ],
    );
  }

  Widget _buildStatusWidget() {
    switch (_loadingState) {
      case LoadingState.loading:
        return LinearProgressIndicator();
      case LoadingState.error:
        return Container(
          padding: EdgeInsets.all(16),
          color: Colors.red.shade50,
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('加载失败', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    Text(_errorMessage, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                  ],
                ),
              ),
              TextButton(
                onPressed: _refresh,
                child: Text('重试'),
              ),
            ],
          ),
        );
      case LoadingState.success:
        if (_objects.isEmpty) {
          return Container(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                SizedBox(height: 16),
                Text('该文件夹为空', style: TextStyle(color: Colors.grey.shade600)),
                SizedBox(height: 8),
                Text('点击右下角按钮上传文件或创建文件夹', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          );
        }
        return Container();
      case LoadingState.idle:
        return Container();
    }
  }

  Widget _buildContent() {
    if (_loadingState == LoadingState.loading && _objects.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }

    if (_objects.isEmpty) {
      return Container();
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _viewMode == ViewMode.grid ? _buildGridView() : _buildListView(),
    );
  }

  /// 构建分页控制器
  Widget _buildPaginationControls() {
    if (_objects.isEmpty) return Container();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 上一页
          IconButton(
            icon: Icon(Icons.chevron_left),
            onPressed: _currentPage > 1 ? _loadPreviousPage : null,
            tooltip: '上一页',
          ),
          // 页码信息
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '第 $_currentPage 页',
              style: TextStyle(fontSize: 14),
            ),
          ),
          // 下一页
          IconButton(
            icon: Icon(Icons.chevron_right),
            onPressed: _hasMore ? _loadNextPage : null,
            tooltip: '下一页',
            disabledColor: Colors.grey.shade400,
          ),
          // 加载更多指示器
          if (_isLoadingMore)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
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
      itemCount: _objects.length,
      itemBuilder: (context, index) {
        final obj = _objects[index];
        final isSelected = _selectedObjects.contains(obj.key);
        final isFolder = obj.type != ObjectType.file;

        return ListTile(
          leading: Icon(_getObjectIcon(obj), color: _getObjectColor(obj)),
          title: Text(obj.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: isFolder
              ? null
              : Text('${_formatBytes(obj.size)} • ${_formatDate(obj.lastModified)}'),
          selected: isSelected,
          selectedTileColor: Colors.blue.withValues(alpha: 0.1),
          trailing: isFolder
              ? null
              : Checkbox(
                  value: isSelected,
                  onChanged: (value) => _toggleSelection(obj),
                ),
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(obj);
            } else {
              logUi('User tapped object: ${obj.name}');
              if (isFolder) {
                _navigateToFolder(obj);
              } else {
                _showObjectActions(obj);
              }
            }
          },
          onLongPress: () {
            logUi('User long pressed object: ${obj.name}');
            _showObjectOptionsMenu(obj);
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
        childAspectRatio: 0.75,
      ),
      padding: EdgeInsets.all(16),
      itemCount: _objects.length,
      itemBuilder: (context, index) {
        final obj = _objects[index];
        final isSelected = _selectedObjects.contains(obj.key);
        final isFolder = obj.type != ObjectType.file;

        return GestureDetector(
          onTap: () {
            if (_isSelectionMode) {
              if (!isFolder) _toggleSelection(obj);
            } else {
              logUi('User tapped object: ${obj.name}');
              if (isFolder) {
                _navigateToFolder(obj);
              } else {
                _showObjectActions(obj);
              }
            }
          },
          onLongPress: () {
            logUi('User long pressed object: ${obj.name}');
            _showObjectOptionsMenu(obj);
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(8),
              color: isSelected ? Colors.blue.withValues(alpha: 0.1) : Colors.white,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getObjectIcon(obj),
                  size: 48,
                  color: _getObjectColor(obj),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    obj.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.blue : Colors.black87,
                    ),
                  ),
                ),
                if (!isFolder)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      _formatBytes(obj.size),
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ),
                if (isFolder && _isSelectionMode)
                  Checkbox(
                    value: isSelected,
                    onChanged: (value) => _toggleSelection(obj),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 进入文件夹
  void _navigateToFolder(ObjectFile folder) {
    logUi('Navigating to folder: ${folder.name}');
    setState(() {
      _currentPrefix = folder.key;
      _currentPage = 1;
      _nextMarker = null;
      _hasMore = false;
    });
    _loadObjects(refresh: true);
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

  /// 根据文件类型获取图标
  IconData _getObjectIcon(ObjectFile obj) {
    if (obj.type == ObjectType.folder) {
      return Icons.folder;
    }

    final ext = obj.extension.toLowerCase();
    switch (ext) {
      // 图片
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
      case 'svg':
        return Icons.image;

      // 视频
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'webm':
        return Icons.video_file;

      // 音频
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
      case 'm4a':
        return Icons.audio_file;

      // 文档
      case 'pdf':
        return Icons.picture_as_pdf;

      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return Icons.description;

      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;

      case 'ppt':
      case 'pptx':
        return Icons.slideshow;

      // 压缩文件
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.archive;

      // 代码
      case 'dart':
      case 'js':
      case 'ts':
      case 'py':
      case 'java':
      case 'c':
      case 'cpp':
      case 'h':
      case 'html':
      case 'css':
      case 'json':
      case 'yaml':
      case 'yml':
        return Icons.code;

      // 可执行文件
      case 'exe':
      case 'app':
      case 'dmg':
        return Icons.play_circle_filled;

      default:
        return Icons.insert_drive_file;
    }
  }

  /// 根据文件类型获取颜色
  Color _getObjectColor(ObjectFile obj) {
    if (obj.type == ObjectType.folder) {
      return Colors.amber.shade700;
    }

    final ext = obj.extension.toLowerCase();
    switch (ext) {
      // 图片 - 紫色
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
      case 'svg':
        return Colors.purple;

      // 视频 - 粉色
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'webm':
        return Colors.pink;

      // 音频 - 青色
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
      case 'm4a':
        return Colors.cyan;

      // 文档 - 蓝色
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return Colors.blue;

      // 表格 - 绿色
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Colors.green;

      // PPT - 橙色
      case 'ppt':
      case 'pptx':
        return Colors.orange;

      // 压缩文件 - 棕色
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Colors.brown;

      // 代码 - 深蓝色
      case 'dart':
      case 'js':
      case 'ts':
      case 'py':
      case 'java':
      case 'c':
      case 'cpp':
      case 'h':
      case 'html':
      case 'css':
      case 'json':
      case 'yaml':
      case 'yml':
        return Colors.indigo;

      // 可执行文件 - 红色
      case 'exe':
      case 'app':
      case 'dmg':
        return Colors.red;

      default:
        return Colors.grey;
    }
  }

  List<Widget> _buildSelectionActions() {
    final fileCount = _objects.where((o) => o.type == ObjectType.file).length;
    final selectedFileCount = _selectedFileList.length;

    return [
      // 全选/取消全选
      IconButton(
        icon: Icon(selectedFileCount == fileCount ? Icons.deselect : Icons.select_all),
        onPressed: fileCount > 0 ? _toggleSelectAll : null,
        tooltip: selectedFileCount == fileCount ? '取消全选' : '全选',
      ),
      // 批量下载
      IconButton(
        icon: Icon(Icons.download),
        onPressed: _selectedObjects.isEmpty ? null : _batchDownload,
        tooltip: '批量下载',
      ),
      // 批量删除
      IconButton(
        icon: Icon(Icons.delete),
        onPressed: _selectedObjects.isEmpty ? null : _batchDelete,
        tooltip: '批量删除',
      ),
    ];
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedObjects.clear();
    });
    logUi('Exited selection mode');
  }

  void _toggleSelection(ObjectFile obj) {
    setState(() {
      if (_selectedObjects.contains(obj.key)) {
        _selectedObjects.remove(obj.key);
        if (_selectedObjects.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedObjects.add(obj.key);
        // 如果不在选择模式，自动进入
        if (!_isSelectionMode) {
          _isSelectionMode = true;
        }
      }
    });
  }

  void _toggleSelectAll() {
    final fileObjects = _objects.where((o) => o.type == ObjectType.file).toList();
    final allSelected = _selectedObjects.length == fileObjects.length;

    setState(() {
      if (allSelected) {
        _selectedObjects.clear();
        if (_selectedObjects.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedObjects.addAll(fileObjects.map((o) => o.key));
        _isSelectionMode = true;
      }
    });

    logUi('Select all: ${!allSelected}, selected: ${_selectedObjects.length} items');
  }

  void _showObjectActions(ObjectFile obj) {
    logUi('Showing actions for object: ${obj.name}');
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.download),
            title: Text('下载'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 下载 for ${obj.name}');
              _downloadObject(obj);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text('删除'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 删除 for ${obj.name}');
              _deleteObject(obj);
            },
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 长按弹出选项菜单
  void _showObjectOptionsMenu(ObjectFile obj) {
    final isFolder = obj.type == ObjectType.folder;

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 文件和文件夹共有的选项
          ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('重命名'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 重命名 for ${obj.name}');
              _handleRename(obj);
            },
          ),
          ListTile(
            leading: Icon(Icons.drive_file_move),
            title: Text('移动到'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 移动到 for ${obj.name}');
              _handleMoveTo(obj);
            },
          ),
          ListTile(
            leading: Icon(Icons.copy),
            title: Text('复制到'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 复制到 for ${obj.name}');
              _handleCopyTo(obj);
            },
          ),
          // 仅文件夹有的选项
          if (isFolder) ...[
            ListTile(
              leading: Icon(Icons.archive),
              title: Text('压缩下载'),
              onTap: () {
                Navigator.pop(context);
                logUi('User selected action: 压缩下载 for ${obj.name}');
                _handleZipDownload(obj);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete),
              title: Text('删除'),
              onTap: () {
                Navigator.pop(context);
                logUi('User selected action: 删除 for ${obj.name}');
                _deleteObject(obj);
              },
            ),
          ],
          SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 重命名处理（留空）
  void _handleRename(ObjectFile obj) {
    // TODO: 实现重命名逻辑
    logUi('Rename not implemented yet for: ${obj.name}');
  }

  /// 移动到处理（留空）
  void _handleMoveTo(ObjectFile obj) {
    // TODO: 实现移动到逻辑
    logUi('Move to not implemented yet for: ${obj.name}');
  }

  /// 复制到处理（留空）
  void _handleCopyTo(ObjectFile obj) {
    // TODO: 实现复制到逻辑
    logUi('Copy to not implemented yet for: ${obj.name}');
  }

  /// 压缩下载处理（留空）
  void _handleZipDownload(ObjectFile obj) {
    // TODO: 实现压缩下载逻辑
    logUi('Zip download not implemented yet for: ${obj.name}');
  }

  Future<void> _downloadObject(ObjectFile obj) async {
    logUi('Starting download for: ${obj.name}');

    // 让用户选择保存位置
    logUi('Opening file picker for save location');
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存文件',
      fileName: obj.name,
    );

    if (savePath == null || savePath.isEmpty) {
      logUi('User cancelled file save dialog');
      return;
    }

    logUi('User selected save path: $savePath');

    // 获取凭证并创建API
    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      logError('No credential found for platform: ${widget.platform}');
      _showErrorSnackBar('下载失败：未找到凭证');
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      _showErrorSnackBar('下载失败：API创建失败');
      return;
    }

    // 进度状态
    int received = 0;
    int total = obj.size > 0 ? obj.size : 1;
    double progress = 0.0;
    void Function(VoidCallback fn)? dialogSetState;

    // 显示下载进度对话框（不阻塞下载）
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            dialogSetState = setState;
            return AlertDialog(
              title: Text('下载中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在下载: ${obj.name}', maxLines: 2),
                  SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: progress,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('${(progress * 100).toInt()}% (${_formatBytes(received)} / ${_formatBytes(total)})'),
                ],
              ),
            );
          },
        );
      },
    );

    // 执行下载（非阻塞）
    logUi('Starting download: ${obj.key}');
    unawaited(api.downloadObject(
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      objectKey: obj.key,
      onProgress: (r, t) {
        dialogSetState?.call(() {
          received = r;
          total = t > 0 ? t : 1;
          progress = total > 0 ? r / total : 0.0;
        });
      },
    ).then((downloadResult) async {
      if (!mounted) return;

      // 关闭进度对话框
      Navigator.of(context).pop();

      if (downloadResult.success && downloadResult.data != null) {
        logUi('Download completed, saving file: ${obj.name}');

        // 保存文件到用户选择的位置
        try {
          final file = File(savePath);
          await file.writeAsBytes(downloadResult.data!);

          logUi('File saved to: $savePath');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('下载成功: ${obj.name}\n保存到: $savePath')),
            );
          }
        } catch (e) {
          logError('Failed to save file: $e');
          _showErrorSnackBar('下载失败：保存文件失败');
        }
      } else {
        logError('Download failed: ${downloadResult.errorMessage}');
        _showErrorSnackBar('下载失败: ${downloadResult.errorMessage}');
      }
    }));
  }

  Future<void> _deleteObject(ObjectFile obj) async {
    logUi('Delete confirmation dialog shown for: ${obj.name}');
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('确定要删除 ${obj.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      logUi('User cancelled delete: ${obj.name}');
      return;
    }

    // 获取凭证并创建API
    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      logError('No credential found for platform: ${widget.platform}');
      _showErrorSnackBar('删除失败：未找到凭证');
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      _showErrorSnackBar('删除失败：API创建失败');
      return;
    }

    // 如果是文件夹，需要递归删除文件夹内的所有对象
    if (obj.type == ObjectType.folder) {
      await _deleteFolder(api, obj.key);
    } else {
      logUi('Starting delete: ${obj.key}');
      final result = await api.deleteObject(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        objectKey: obj.key,
      );

      if (!mounted) return;

      if (result.success) {
        logUi('Delete successful: ${obj.name}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除成功: ${obj.name}')),
        );
        // 刷新文件列表
        _refresh();
      } else {
        logError('Delete failed: ${result.errorMessage}');
        _showErrorSnackBar('删除失败: ${result.errorMessage}');
      }
    }
  }

  /// 递归删除文件夹及其所有内容
  Future<void> _deleteFolder(ICloudPlatformApi api, String folderKey) async {
    logUi('Starting delete folder: $folderKey');

    // 获取文件夹内的所有对象（不使用delimiter，递归列出所有对象）
    String? marker;
    int totalFailed = 0;

    while (true) {
      final listResult = await api.listObjects(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        prefix: folderKey,
        delimiter: '', // 不使用delimiter，获取所有对象
        maxKeys: 1000,
        marker: marker,
      );

      if (!mounted) return;

      if (!listResult.success || listResult.data == null) {
        logError('Failed to list folder contents: ${listResult.errorMessage}');
        _showErrorSnackBar('删除失败：无法列出文件夹内容');
        return;
      }

      final objects = listResult.data!.objects;

      // 收集除文件夹标记外的所有对象key
      final objectKeys = objects
          .where((obj) => obj.key != folderKey)
          .map((obj) => obj.key)
          .toList();

      // 批量删除对象
      if (objectKeys.isNotEmpty) {
        logUi('Batch deleting ${objectKeys.length} objects in folder: $folderKey');
        final deleteResult = await api.deleteObjects(
          bucketName: widget.bucket.name,
          region: widget.bucket.region,
          objectKeys: objectKeys,
        );

        if (deleteResult.success) {
          logUi('Batch delete completed: ${objectKeys.length} objects');
        } else {
          totalFailed += objectKeys.length;
          logError('Batch delete failed: ${deleteResult.errorMessage}');
        }
      }

      // 检查是否还有更多对象
      if (listResult.data!.isTruncated) {
        marker = listResult.data!.nextMarker;
      } else {
        break;
      }
    }

    // 最后删除文件夹标记对象
    logUi('Deleting folder marker: $folderKey');
    final result = await api.deleteObject(
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      objectKey: folderKey,
    );

    if (!mounted) return;

    if (result.success) {
      logUi('Delete folder successful: $folderKey');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除文件夹 "${_getFolderName(folderKey)}"${totalFailed > 0 ? '，$totalFailed 个失败' : ''}')),
      );
      // 刷新文件列表
      _refresh();
    } else {
      logError('Delete folder failed: ${result.errorMessage}');
      _showErrorSnackBar('删除失败: ${result.errorMessage}');
    }
  }

  Future<void> _uploadFiles() async {
    logUi('User tapped upload button');

    // 弹出文件选择器，支持多选
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) {
      logUi('User cancelled file selection');
      return;
    }

    final files = result.files;
    logUi('Selected ${files.length} files');

    if (!mounted) return;

    // 获取凭证并创建API
    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      logError('No credential found for platform: ${widget.platform}');
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      return;
    }

    // 显示进度对话框
    int currentIndex = 0;
    String currentFile = '';
    double currentProgress = 0.0;
    void Function(VoidCallback fn)? dialogSetState;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            dialogSetState = setState;
            return AlertDialog(
              title: Text('上传文件中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在上传: $currentFile', maxLines: 2),
                  SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: currentProgress,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('${(currentProgress * 100).toInt()}%'),
                  SizedBox(height: 8),
                  Text('$currentIndex/${files.length}'),
                ],
              ),
            );
          },
        );
      },
    );

    // 上传每个文件
    int successCount = 0;
    int failCount = 0;

    for (final pickedFile in files) {
      if (pickedFile.path == null) continue;

      final fileSize = pickedFile.size;
      const largeFileThreshold = 100 * 1024 * 1024; // 100MB
      final objectKey = _currentPrefix + pickedFile.name;

      currentIndex++;
      currentFile = pickedFile.name;
      currentProgress = 0.0;

      // 更新对话框进度
      if (mounted) {
        dialogSetState?.call(() {});
      }

      logUi('Uploading file: ${pickedFile.name}, size: ${pickedFile.size} bytes');

      // 大文件使用分块上传，小文件使用简单上传
      if (fileSize > largeFileThreshold) {
        final result = await api.uploadObjectMultipart(
          bucketName: widget.bucket.name,
          region: widget.bucket.region,
          objectKey: objectKey,
          file: File(pickedFile.path!),
          chunkSize: 64 * 1024 * 1024, // 64MB 分块
          onProgress: (sent, total) {
            dialogSetState?.call(() {
              currentProgress = total > 0 ? sent / total : 0.0;
            });
          },
          onStatusChanged: (status) {},
        );
        if (result.success) {
          successCount++;
        } else {
          failCount++;
        }
      } else {
        final fileBytes = await _readFileBytes(pickedFile);
        if (fileBytes == null) {
          failCount++;
          continue;
        }
        final result = await api.uploadObject(
          bucketName: widget.bucket.name,
          region: widget.bucket.region,
          objectKey: objectKey,
          data: fileBytes,
          onProgress: (sent, total) {
            dialogSetState?.call(() {
              currentProgress = total > 0 ? sent / total : 0.0;
            });
          },
        );
        if (result.success) {
          successCount++;
        } else {
          failCount++;
        }
      }
    }

    // 关闭进度对话框并显示结果
    if (mounted) {
      Navigator.of(context).pop();
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功上传 $successCount 个文件${failCount > 0 ? '，$failCount 个失败' : ''}')),
        );
      }
      if (failCount > 0 && successCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败：所有文件上传失败')),
        );
      }
      // 刷新文件列表
      _refresh();
    }
  }

  /// 批量下载
  Future<void> _batchDownload() async {
    final selectedFiles = _selectedFileList;
    if (selectedFiles.isEmpty) return;

    logUi('Batch download: ${selectedFiles.length} files');

    // 让用户选择保存目录
    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存位置',
    );

    if (directoryPath == null || directoryPath.isEmpty) {
      logUi('User cancelled directory selection');
      return;
    }

    logUi('Selected directory: $directoryPath');

    // 获取凭证并创建API
    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      logError('No credential found for platform: ${widget.platform}');
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      return;
    }

    int successCount = 0;
    int failCount = 0;

    // 显示进度对话框
    int currentIndex = 0;
    String currentFile = '';
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('批量下载中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在下载: $currentFile', maxLines: 2),
                  SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: currentIndex / selectedFiles.length,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('$currentIndex/${selectedFiles.length}'),
                ],
              ),
            );
          },
        );
      },
    );

    // 逐个下载文件
    for (final obj in selectedFiles) {
      currentFile = obj.name;
      currentIndex++;

      // 更新对话框进度
      if (mounted) {
        setState(() {});
      }

      logUi('Downloading: ${obj.name}');
      final result = await api.downloadObject(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        objectKey: obj.key,
        onProgress: (r, t) {},
      );

      if (result.success && result.data != null) {
        try {
          final savePath = '$directoryPath/${obj.name}';
          final file = File(savePath);
          await file.writeAsBytes(result.data!);
          successCount++;
          logUi('Downloaded: ${obj.name} -> $savePath');
        } catch (e) {
          failCount++;
          logError('Failed to save file: ${obj.name}, $e');
        }
      } else {
        failCount++;
        logError('Download failed: ${obj.name}, ${result.errorMessage}');
      }
    }

    // 关闭进度对话框并显示结果
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功下载 $successCount 个文件${failCount > 0 ? '，$failCount 个失败' : ''}')),
      );
      // 退出选择模式
      _exitSelectionMode();
    }
  }

  /// 批量删除
  Future<void> _batchDelete() async {
    final selectedFiles = _selectedFileList;
    if (selectedFiles.isEmpty) return;

    logUi('Batch delete: ${selectedFiles.length} files');

    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('确定要删除选中的 ${selectedFiles.length} 个文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      logUi('User cancelled batch delete');
      return;
    }

    // 获取凭证并创建API
    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      logError('No credential found for platform: ${widget.platform}');
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      return;
    }

    int successCount = 0;
    int failCount = 0;

    // 批量删除文件
    final objectKeys = selectedFiles.map((obj) => obj.key).toList();
    logUi('Deleting: ${objectKeys.length} objects in batch');
    final result = await api.deleteObjects(
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      objectKeys: objectKeys,
    );

    if (result.success) {
      successCount = objectKeys.length;
      logUi('Batch delete completed: $successCount objects');
    } else {
      failCount = objectKeys.length;
      logError('Batch delete failed: ${result.errorMessage}');
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('成功删除 $successCount 个文件${failCount > 0 ? '，$failCount 个失败' : ''}')),
    );
    // 等待一段时间后再刷新（腾讯云COS使用最终一致性模型）
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    // 刷新文件列表并退出选择模式
    _refresh();
    _exitSelectionMode();
  }

  /// 读取文件字节
  Future<Uint8List?> _readFileBytes(PlatformFile file) async {
    try {
      if (file.path != null) {
        final fileEntity = File(file.path!);
        return await fileEntity.readAsBytes();
      }
      return file.bytes;
    } catch (e) {
      logError('Failed to read file: $e');
      return null;
    }
  }

  /// 格式化日期时间
  String _formatDate(DateTime? date) {
    if (date == null) return '未知';
    return '${date.year}-${_pad(date.month)}-${_pad(date.day)} ${_pad(date.hour)}:${_pad(date.minute)}';
  }

  /// 补零
  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 格式化字节大小
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 从文件夹key中提取文件夹名称（如 "AAA/" -> "AAA"）
  String _getFolderName(String folderKey) {
    if (folderKey.endsWith('/')) {
      folderKey = folderKey.substring(0, folderKey.length - 1);
    }
    return folderKey.split('/').where((e) => e.isNotEmpty).lastOrNull ?? folderKey;
  }
}
