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
import 'widgets/export.dart';

// ignore_for_file: library_private_types_in_public_api

/// 视图模式枚举
enum ViewMode { list, grid }

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
  List<ObjectFile> _originalObjects = [];
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

  // 排序模式
  SortMode _sortMode = SortMode.none;

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

  @override
  void dispose() {
    _clipboardFiles.clear();
    _isCutOperation = false;
    super.dispose();
  }

  // ==================== 数据加载 ====================

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

    logUi(
      'Loading objects for bucket: ${widget.bucket.name}, prefix: "$_currentPrefix", page: $_currentPage',
    );

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
        setState(() {
          _objects = result.data!.objects;
          _originalObjects = List.from(_objects);
          _hasMore = result.data!.isTruncated;
          _nextMarker = result.data!.nextMarker;
          _loadingState = LoadingState.success;
          _errorMessage = '';
          _isLoadingMore = false;
          _applySort();
        });
        logUi(
          'Loaded ${_objects.length} objects, hasMore: $_hasMore, page: $_currentPage',
        );
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

  void _loadNextPage() {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    _loadObjects();
  }

  void _loadPreviousPage() {
    if (_isLoadingMore || _currentPage <= 1) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage--;
    });
    _loadObjects();
  }

  Future<void> _refresh() async {
    _currentPage = 1;
    _nextMarker = null;
    _hasMore = false;
    await _loadObjects(refresh: true);
  }

  // ==================== 排序 ====================

  void _applySort() {
    setState(() {
      switch (_sortMode) {
        case SortMode.nameAsc:
          _objects.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          break;
        case SortMode.nameDesc:
          _objects.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
          );
          break;
        case SortMode.timeAsc:
          _objects.sort((a, b) {
            final timeA = a.lastModified ?? DateTime(1970);
            final timeB = b.lastModified ?? DateTime(1970);
            return timeA.compareTo(timeB);
          });
          break;
        case SortMode.timeDesc:
          _objects.sort((a, b) {
            final timeA = a.lastModified ?? DateTime(1970);
            final timeB = b.lastModified ?? DateTime(1970);
            return timeB.compareTo(timeA);
          });
          break;
        case SortMode.none:
          _objects = List.from(_originalObjects);
          break;
      }
    });
  }

  void _sortByName() {
    setState(() {
      if (_sortMode == SortMode.nameAsc) {
        _sortMode = SortMode.nameDesc;
      } else {
        _sortMode = SortMode.nameAsc;
      }
      _applySort();
    });
    logUi('Sort by name: ${_sortMode.name}');
  }

  void _sortByTime() {
    setState(() {
      if (_sortMode == SortMode.timeAsc) {
        _sortMode = SortMode.timeDesc;
      } else {
        _sortMode = SortMode.timeAsc;
      }
      _applySort();
    });
    logUi('Sort by time: ${_sortMode.name}');
  }

  // ==================== 导航 ====================

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

  // ==================== 视图模式 ====================

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
    });
    logUi('View mode changed to: ${_viewMode.name}');
  }

  int _getCrossAxisCount() {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 900) return 5;
    if (width > 600) return 4;
    if (width > 400) return 3;
    return 2;
  }

  // ==================== 选择模式 ====================

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
        if (!_isSelectionMode) {
          _isSelectionMode = true;
        }
      }
    });
  }

  void _toggleSelectAll() {
    final fileObjects = _objects
        .where((o) => o.type == ObjectType.file)
        .toList();
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

    logUi(
      'Select all: ${!allSelected}, selected: ${_selectedObjects.length} items',
    );
  }

  List<Widget> _buildSelectionActions() {
    final fileCount = _objects.where((o) => o.type == ObjectType.file).length;
    final selectedFileCount = _selectedFileList.length;

    return [
      IconButton(
        icon: Icon(
          selectedFileCount == fileCount ? Icons.deselect : Icons.select_all,
        ),
        onPressed: fileCount > 0 ? _toggleSelectAll : null,
        tooltip: selectedFileCount == fileCount ? '取消全选' : '全选',
      ),
      IconButton(
        icon: const Icon(Icons.download),
        onPressed: _selectedObjects.isEmpty ? null : _batchDownload,
        tooltip: '批量下载',
      ),
      IconButton(
        icon: const Icon(Icons.delete),
        onPressed: _selectedObjects.isEmpty ? null : _batchDelete,
        tooltip: '批量删除',
      ),
    ];
  }

  // ==================== 添加选项 ====================

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasClipboardContent)
            ListTile(
              leading: Stack(
                children: [
                  const Icon(Icons.content_paste),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              title: const Text('粘贴'),
              subtitle: Text(_clipboardFiles[0].name),
              onTap: () {
                Navigator.pop(context);
                _handlePaste();
              },
            ),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: const Text('上传文件'),
            onTap: () {
              Navigator.pop(context);
              _uploadFiles();
            },
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder),
            title: const Text('新建文件夹'),
            onTap: () {
              Navigator.pop(context);
              _showCreateFolderDialog();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('文件夹 "$folderName" 创建成功')));
      _refresh();
    } else {
      _showErrorSnackBar(result.errorMessage ?? '创建失败');
    }
  }

  void _showCreateFolderDialog() {
    showCreateFolderDialog(
      context,
      existingObjects: _objects,
      onCreate: _createFolder,
    );
  }

  // ==================== 对象操作 ====================

  void _showObjectActions(ObjectFile obj) {
    logUi('Showing actions for object: ${obj.name}');
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('下载'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 下载 for ${obj.name}');
              _downloadObject(obj);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('删除'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 删除 for ${obj.name}');
              _deleteObject(obj);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showObjectOptionsMenu(ObjectFile obj) {
    final isFolder = obj.type == ObjectType.folder;

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('重命名'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 重命名 for ${obj.name}');
              _showRenameDialog(obj);
            },
          ),
          ListTile(
            leading: const Icon(Icons.cut),
            title: const Text('剪切'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 剪切 for ${obj.name}');
              _handleCut(obj);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制'),
            onTap: () {
              Navigator.pop(context);
              logUi('User selected action: 复制 for ${obj.name}');
              _handleCopy(obj);
            },
          ),
          if (isFolder) ...[
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载'),
              onTap: () {
                Navigator.pop(context);
                logUi('User selected action: 下载 for ${obj.name}');
                _handleFolderDownload(obj);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('删除'),
              onTap: () {
                Navigator.pop(context);
                logUi('User selected action: 删除 for ${obj.name}');
                _deleteObject(obj);
              },
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showRenameDialog(ObjectFile obj) {
    showRenameDialog(
      context,
      objectFile: obj,
      existingObjects: _objects,
      onRename: (newName) => _renameObject(obj, newName),
    );
  }

  Future<void> _renameObject(ObjectFile obj, String newName) async {
    logUi('Renaming object: ${obj.name} -> $newName');

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

    final result = await api.renameObject(
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      sourceKey: obj.key,
      newName: newName,
      prefix: _currentPrefix,
    );

    if (!mounted) return;

    if (result.success) {
      logUi('Rename successful: ${obj.name} -> $newName');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('重命名成功')));
      _refresh();
    } else {
      _showErrorSnackBar(result.errorMessage ?? '重命名失败');
    }
  }

  // ==================== 剪贴板 ====================

  static List<ObjectFile> _clipboardFiles = [];
  static bool _isCutOperation = false;

  void _handleCut(ObjectFile obj) {
    logUi('Cut: ${obj.name}');
    _clipboardFiles = [obj];
    _isCutOperation = true;
    setState(() {});
  }

  void _handleCopy(ObjectFile obj) {
    logUi('Copy: ${obj.name}');
    _clipboardFiles = [obj];
    _isCutOperation = false;
    setState(() {});
  }

  void _clearClipboard() {
    _clipboardFiles.clear();
    _isCutOperation = false;
    if (mounted) {
      setState(() {});
    }
    logUi('Clipboard cleared');
  }

  bool get _hasClipboardContent => _clipboardFiles.isNotEmpty;

  bool _isSourceInTargetPath(String sourceKey, String targetPrefix) {
    if (!sourceKey.endsWith('/')) return false;
    final normalizedSource =
        sourceKey.endsWith('/') ? sourceKey : '$sourceKey/';
    final normalizedTarget =
        targetPrefix.endsWith('/') ? targetPrefix : '$targetPrefix/';
    return normalizedTarget.startsWith(normalizedSource);
  }

  Future<void> _handlePaste() async {
    if (!_hasClipboardContent) {
      _showErrorSnackBar('剪贴板为空');
      return;
    }

    final targetPrefix = _currentPrefix;

    for (final obj in _clipboardFiles) {
      if (_isSourceInTargetPath(obj.key, targetPrefix)) {
        _showErrorSnackBar('无法将文件夹粘贴到其子目录中');
        return;
      }

      final targetKey = targetPrefix + obj.name;
      if (_objects.any(
        (existing) => existing.key == targetKey || existing.name == obj.name,
      )) {
        _showErrorSnackBar('目标目录已存在 "${obj.name}"，无法粘贴');
        return;
      }
    }

    logUi(
      'Pasting ${_clipboardFiles.length} items to: $targetPrefix, isCut: $_isCutOperation',
    );

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

    int successCount = 0;
    int failCount = 0;

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
              title: Text(_isCutOperation ? '移动中' : '复制中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在处理: $currentFile', maxLines: 2),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: _clipboardFiles.isNotEmpty
                          ? currentIndex / _clipboardFiles.length
                          : 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('$currentIndex/${_clipboardFiles.length}'),
                ],
              ),
            );
          },
        );
      },
    );

    for (final obj in _clipboardFiles) {
      currentIndex++;
      currentFile = obj.name;

      try {
        final targetKey = targetPrefix + obj.name;

        if (obj.type == ObjectType.folder) {
          final copyResult = await api.copyFolder(
            bucketName: widget.bucket.name,
            region: widget.bucket.region,
            sourceFolderKey: obj.key,
            targetFolderKey: targetKey,
          );

          if (!copyResult.success) {
            failCount++;
            logError(
              'Failed to copy folder: ${obj.name}, ${copyResult.errorMessage}',
            );
            continue;
          }
        } else {
          final copyResult = await api.copyObject(
            bucketName: widget.bucket.name,
            region: widget.bucket.region,
            sourceKey: obj.key,
            targetKey: targetKey,
          );

          if (!copyResult.success) {
            failCount++;
            logError('Failed to copy: ${obj.name}, ${copyResult.errorMessage}');
            continue;
          }
        }

        if (_isCutOperation) {
          if (obj.type == ObjectType.folder) {
            await api.deleteFolder(
              bucketName: widget.bucket.name,
              region: widget.bucket.region,
              folderKey: obj.key,
            );
          } else {
            await api.deleteObject(
              bucketName: widget.bucket.name,
              region: widget.bucket.region,
              objectKey: obj.key,
            );
          }
        }

        successCount++;
        logUi(
          'Successfully ${_isCutOperation ? 'moved' : 'copied'}: ${obj.name}',
        );
      } catch (e) {
        failCount++;
        logError('Failed to process: ${obj.name}, $e');
      }

      if (!mounted) return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    _clearClipboard();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isCutOperation
              ? '成功移动 $successCount 个${failCount > 0 ? '，$failCount 个失败' : ''}'
              : '成功复制 $successCount 个${failCount > 0 ? '，$failCount 个失败' : ''}',
        ),
      ),
    );

    _refresh();
  }

  // ==================== 下载 ====================

  Future<void> _downloadObject(ObjectFile obj) async {
    logUi('Starting download for: ${obj.name}');

    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存位置',
    );

    if (directoryPath == null || directoryPath.isEmpty) {
      logUi('User cancelled directory selection');
      return;
    }

    logUi('Selected directory: $directoryPath');

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

    int received = 0;
    int total = obj.size > 0 ? obj.size : 1;
    double progress = 0.0;
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
              title: const Text('下载中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在下载: ${obj.name}', maxLines: 2),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(value: progress),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(progress * 100).toInt()}% (${_formatBytes(received)} / ${_formatBytes(total)})',
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    final savePath = '$directoryPath/${obj.name}';
    final saveFile = File(savePath);
    saveFile.parent.createSync(recursive: true);

    final fileSize = obj.size;
    const largeFileThreshold = 100 * 1024 * 1024; // 100MB
    final isLargeFile = fileSize > largeFileThreshold;

    logUi(
        'Starting download: ${obj.key}, size: $fileSize bytes, mode: ${isLargeFile ? 'multipart' : 'normal'}');

    ApiResponse<void> downloadResult;
    if (isLargeFile) {
      downloadResult = await api.downloadObjectMultipart(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        objectKey: obj.key,
        outputFile: saveFile,
        chunkSize: 64 * 1024 * 1024,
        onProgress: (r, t) {
          dialogSetState?.call(() {
            received = r;
            total = t > 0 ? t : 1;
            progress = total > 0 ? r / total : 0.0;
          });
        },
      );
    } else {
      downloadResult = await api.downloadObject(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        objectKey: obj.key,
        outputFile: saveFile,
        onProgress: (r, t) {
          dialogSetState?.call(() {
            received = r;
            total = t > 0 ? t : 1;
            progress = total > 0 ? r / total : 0.0;
          });
        },
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (downloadResult.success) {
      logUi('Download completed, file saved to: $savePath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载成功: ${obj.name}\n保存到: $savePath'),
          ),
        );
      }
    } else {
      logError('Download failed: ${downloadResult.errorMessage}');
      _showErrorSnackBar('下载失败: ${downloadResult.errorMessage}');
    }
  }

  Future<void> _handleFolderDownload(ObjectFile folder) async {
    assert(folder.type == ObjectType.folder, 'Only folders can be downloaded');

    logUi('Starting folder download for: ${folder.name}');

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

    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存位置',
    );

    if (directoryPath == null || directoryPath.isEmpty) {
      logUi('User cancelled directory selection');
      return;
    }

    logUi('Selected directory: $directoryPath');

    int dialogCurrent = 0;
    int dialogTotal = 0;
    String dialogMessage = '';
    bool isDialogShowing = false;
    void Function(VoidCallback fn)? dialogSetState;

    void showProgressDialog() {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            dialogSetState = setState;
            return AlertDialog(
              title: const Text('下载中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dialogMessage, maxLines: 2),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: dialogTotal > 0 ? dialogCurrent / dialogTotal : 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('$dialogCurrent / $dialogTotal'),
                ],
              ),
            );
          },
        ),
      ).then((_) {
        isDialogShowing = false;
      });
      isDialogShowing = true;
    }

    void updateProgress(int current, int total, String message) {
      dialogCurrent = current;
      dialogTotal = total;
      dialogMessage = message;
      if (isDialogShowing) {
        dialogSetState?.call(() {});
      } else {
        showProgressDialog();
      }
    }

    void closeProgressDialog() {
      if (isDialogShowing && mounted) {
        Navigator.of(context).pop();
        isDialogShowing = false;
      }
    }

    try {
      updateProgress(0, 0, '正在扫描文件...');

      final allObjects = await _listAllObjects(api, folder.key);

      if (!mounted) return;

      final fileObjects =
          allObjects.where((obj) => !obj.key.endsWith('/')).toList();

      if (fileObjects.isEmpty) {
        closeProgressDialog();
        _showErrorSnackBar('文件夹为空');
        return;
      }

      logUi('Found ${fileObjects.length} file objects (excluding folder markers)');

      closeProgressDialog();
      await Future.delayed(const Duration(milliseconds: 100));

      int downloadedCount = 0;
      int failedCount = 0;

      for (final obj in fileObjects) {
        if (!mounted) return;

        final relativePath = obj.key.substring(folder.key.length);
        final savePath = '$directoryPath/${folder.name}/$relativePath';
        final saveFile = File(savePath);
        saveFile.parent.createSync(recursive: true);

        updateProgress(
          downloadedCount + failedCount,
          fileObjects.length,
          '正在下载: ${obj.name}',
        );

        final result = await api.downloadObject(
          bucketName: widget.bucket.name,
          region: widget.bucket.region,
          objectKey: obj.key,
          outputFile: saveFile,
          onProgress: (r, t) {},
        );

        if (result.success) {
        } else {
          failedCount++;
          logError('Failed to download: ${obj.name}');
        }
      }

      if (!mounted) return;

      closeProgressDialog();

      if (downloadedCount == 0) {
        _showErrorSnackBar('下载文件失败');
        return;
      }

      final targetDir = '$directoryPath/${folder.name}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '下载完成\n保存到: $targetDir\n成功: $downloadedCount 个${failedCount > 0 ? '，失败: $failedCount 个' : ''}',
          ),
        ),
      );
    } catch (e) {
      logError('Folder download failed: $e');
      if (mounted) {
        _showErrorSnackBar('下载失败: $e');
      }
    } finally {
      closeProgressDialog();
    }
  }

  Future<List<ObjectFile>> _listAllObjects(
    ICloudPlatformApi api,
    String prefix,
  ) async {
    final allObjects = <ObjectFile>[];
    String? marker;

    while (true) {
      final result = await api.listObjects(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        prefix: prefix,
        delimiter: '',
        maxKeys: 1000,
        marker: marker,
      );

      if (!result.success || result.data == null) {
        logError('Failed to list objects: ${result.errorMessage}');
        break;
      }

      allObjects.addAll(result.data!.objects);

      if (result.data!.isTruncated) {
        marker = result.data!.nextMarker;
      } else {
        break;
      }
    }

    return allObjects;
  }

  // ==================== 删除 ====================

  Future<void> _deleteObject(ObjectFile obj) async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      objectName: obj.name,
    );

    if (confirmed != true) {
      logUi('User cancelled delete: ${obj.name}');
      return;
    }

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除成功: ${obj.name}')));
        _refresh();
      } else {
        logError('Delete failed: ${result.errorMessage}');
        _showErrorSnackBar('删除失败: ${result.errorMessage}');
      }
    }
  }

  Future<void> _deleteFolder(ICloudPlatformApi api, String folderKey) async {
    logUi('Starting delete folder: $folderKey');

    final result = await api.deleteFolder(
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      folderKey: folderKey,
    );

    if (!mounted) return;

    if (result.success) {
      logUi('Delete folder successful: $folderKey');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除文件夹 "${_getFolderName(folderKey)}"')),
      );
      _refresh();
    } else {
      logError('Delete folder failed: ${result.errorMessage}');
      _showErrorSnackBar('删除失败: ${result.errorMessage}');
    }
  }

  // ==================== 上传 ====================

  Future<void> _uploadFiles() async {
    logUi('User tapped upload button');

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result == null || result.files.isEmpty) {
      logUi('User cancelled file selection');
      return;
    }

    final files = result.files;
    logUi('Selected ${files.length} files');

    if (!mounted) return;

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
              title: const Text('上传文件中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在上传: $currentFile', maxLines: 2),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(value: currentProgress),
                  ),
                  const SizedBox(height: 8),
                  Text('${(currentProgress * 100).toInt()}%'),
                  const SizedBox(height: 8),
                  Text('$currentIndex/${files.length}'),
                ],
              ),
            );
          },
        );
      },
    );

    int successCount = 0;
    int failCount = 0;

    for (final pickedFile in files) {
      if (pickedFile.path == null) continue;

      final fileSize = pickedFile.size;
      const largeFileThreshold = 100 * 1024 * 1024;
      final objectKey = _currentPrefix + pickedFile.name;

      currentIndex++;
      currentFile = pickedFile.name;
      currentProgress = 0.0;

      if (mounted) {
        dialogSetState?.call(() {});
      }

      logUi(
        'Uploading file: ${pickedFile.name}, size: ${pickedFile.size} bytes',
      );

      if (fileSize > largeFileThreshold) {
        final result = await api.uploadObjectMultipart(
          bucketName: widget.bucket.name,
          region: widget.bucket.region,
          objectKey: objectKey,
          file: File(pickedFile.path!),
          chunkSize: 64 * 1024 * 1024,
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

    if (!mounted) return;
    Navigator.of(context).pop();
    if (successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '成功上传 $successCount 个文件${failCount > 0 ? '，$failCount 个失败' : ''}',
          ),
        ),
      );
    }
    if (failCount > 0 && successCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('上传失败：所有文件上传失败')));
    }
    _refresh();
  }

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

  // ==================== 批量操作 ====================

  Future<void> _batchDownload() async {
    final selectedFiles = _selectedFileList;
    if (selectedFiles.isEmpty) return;
    if (!mounted) return;

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

    if (!mounted) return;
    await BatchOperations.batchDownload(
      context: context,
      selectedFiles: selectedFiles,
      api: api,
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      onComplete: _exitSelectionMode,
      onError: _showErrorSnackBar,
    );
  }

  Future<void> _batchDelete() async {
    final selectedFiles = _selectedFileList;
    if (selectedFiles.isEmpty) return;

    final confirmed = await showBatchDeleteConfirmDialog(
      context,
      fileCount: selectedFiles.length,
    );

    if (confirmed != true) {
      logUi('User cancelled batch delete');
      return;
    }

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

    if (!mounted) return;
    await BatchOperations.batchDelete(
      context: context,
      selectedFiles: selectedFiles,
      api: api,
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      onSuccess: () {
        _refresh();
        _exitSelectionMode();
      },
      onError: _showErrorSnackBar,
    );
  }

  // ==================== UI 构建 ====================

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
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode)
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
                tooltip: '返回',
              ),
      ),
      body: _buildBody(),
      floatingActionButton: _isSelectionMode
          ? null
          : Stack(
              children: [
                FloatingActionButton(
                  tooltip: '添加',
                  onPressed: _showAddOptions,
                  child: const Icon(Icons.add),
                ),
                if (_hasClipboardContent)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

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

  Widget _buildBody() {
    return Column(
      children: [
        PathNavigation(
          pathSegments: _pathSegments,
          onNavigateToRoot: _navigateToRoot,
          onNavigateToPrefix: _navigateToPrefix,
        ),
        // 只有在 loading/error 状态时才显示 StatusWidgets
        // 空状态由 Expanded 区域处理（显示"该文件夹为空"）
        if (_loadingState == LoadingState.loading ||
            _loadingState == LoadingState.error)
          StatusWidgets(
            loadingState: _loadingState,
            errorMessage: _errorMessage,
            onRetry: _refresh,
          ),
        // 使用 Visibility 替代 Expanded，确保空数据时不占空间
        Visibility(
          visible: _objects.isNotEmpty,
          maintainState: false,
          child: Expanded(child: _buildContent()),
        ),
        // 空数据时在 Expanded 区域显示空状态
        if (_objects.isEmpty && _loadingState == LoadingState.success)
          Expanded(child: _buildEmptyState()),
        // 只有在有数据时才显示分页控制器
        if (_objects.isNotEmpty)
          PaginationControls(
            currentPage: _currentPage,
            hasMore: _hasMore,
            isLoadingMore: _isLoadingMore,
            sortMode: _sortMode,
            onPreviousPage: _loadPreviousPage,
            onNextPage: _loadNextPage,
            onSortByName: _sortByName,
            onSortByTime: _sortByTime,
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('该文件夹为空', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮上传文件或创建文件夹',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // 有数据时构建列表视图
    return _viewMode == ViewMode.grid ? _buildGridView() : _buildListView();
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _objects.length,
      itemBuilder: (context, index) {
        final obj = _objects[index];
        final isSelected = _selectedObjects.contains(obj.key);
        final isFolder = obj.type != ObjectType.file;

        return ObjectListItem(
          objectFile: obj,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
          isFolder: isFolder,
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
          onCheckboxChanged: () => _toggleSelection(obj),
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getCrossAxisCount(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      padding: const EdgeInsets.all(16),
      itemCount: _objects.length,
      itemBuilder: (context, index) {
        final obj = _objects[index];
        final isSelected = _selectedObjects.contains(obj.key);
        final isFolder = obj.type != ObjectType.file;

        return ObjectGridItem(
          objectFile: obj,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
          isFolder: isFolder,
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
          onCheckboxChanged: () => _toggleSelection(obj),
        );
      },
    );
  }

  Widget _buildViewModeToggle() {
    return IconButton(
      icon: Icon(
        _viewMode == ViewMode.list ? Icons.grid_view : Icons.view_list,
      ),
      onPressed: _toggleViewMode,
      tooltip: _viewMode == ViewMode.list ? '网格视图' : '列表视图',
    );
  }

  // ==================== 工具方法 ====================

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _getFolderName(String folderKey) {
    if (folderKey.endsWith('/')) {
      folderKey = folderKey.substring(0, folderKey.length - 1);
    }
    return folderKey.split('/').where((e) => e.isNotEmpty).lastOrNull ??
        folderKey;
  }
}
