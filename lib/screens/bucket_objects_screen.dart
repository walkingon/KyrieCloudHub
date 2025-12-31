import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/bucket.dart';
import '../models/object_file.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';

// ignore_for_file: library_private_types_in_public_api

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
  bool _isLoading = true;
  late final StorageService _storage;
  late final CloudPlatformFactory _factory;

  // 多选模式相关
  bool _isSelectionMode = false;
  final Set<String> _selectedObjects = {};
  List<ObjectFile> get _selectedFileList =>
      _objects.where((obj) => _selectedObjects.contains(obj.key)).toList();

  @override
  void initState() {
    super.initState();
    logUi('BucketObjectsScreen initialized for bucket: ${widget.bucket.name}');
    _storage = Provider.of<StorageService>(context, listen: false);
    _factory = Provider.of<CloudPlatformFactory>(context, listen: false);
    _loadObjects();
  }

  Future<void> _loadObjects() async {
    setState(() {
      _isLoading = true;
    });

    logUi('Loading objects for bucket: ${widget.bucket.name}');
    final credential = await _storage.getCredential(widget.platform);
    if (credential != null) {
      final api = _factory.createApi(widget.platform, credential: credential);
      if (api != null) {
        final result = await api.listObjects(
          bucketName: widget.bucket.name,
          region: widget.bucket.region,
        );
        if (result.success) {
          if (mounted) {
            setState(() {
              _objects = result.data?.objects ?? [];
            });
          }
          logUi('Loaded ${_objects.length} objects from bucket: ${widget.bucket.name}');
        } else {
          logError('Failed to load objects: ${result.errorMessage}');
        }
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('已选择 ${_selectedObjects.length} 项')
            : Text(widget.bucket.name),
        actions: _isSelectionMode ? _buildSelectionActions() : null,
        leading: _isSelectionMode
            ? IconButton(
                icon: Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView.builder(
                  itemCount: _objects.length,
                  itemBuilder: (context, index) {
                    final obj = _objects[index];
                    final isSelected = _selectedObjects.contains(obj.key);
                    // 文件夹不允许选择（暂不支持文件夹操作）
                    final isFolder = obj.type != ObjectType.file;

                    return ListTile(
                      leading: Icon(
                        isFolder ? Icons.folder : Icons.insert_drive_file,
                      ),
                      title: Text(obj.name),
                      subtitle: Text(obj.lastModified?.toString() ?? ''),
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
                          _showObjectActions(obj);
                        }
                      },
                      onLongPress: isFolder
                          ? null
                          : () {
                              logUi('User long pressed object: ${obj.name}');
                              _enterSelectionMode(obj);
                            },
                    );
                  },
                ),
              ],
            ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton(
              onPressed: _uploadFiles,
              child: Icon(Icons.add),
            ),
    );
  }

  List<Widget> _buildSelectionActions() {
    return [
      // 全选/取消全选
      IconButton(
        icon: Icon(_selectedObjects.length == _objects.where((o) => o.type == ObjectType.file).length
            ? Icons.deselect
            : Icons.select_all),
        onPressed: _toggleSelectAll,
        tooltip: '全选',
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

  void _enterSelectionMode(ObjectFile obj) {
    setState(() {
      _isSelectionMode = true;
      _selectedObjects.add(obj.key);
    });
    logUi('Entered selection mode, selected: ${obj.name}');
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
      builder: (context) {
        return Column(
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
          ],
        );
      },
    );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败：未找到凭证')),
        );
      }
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败：API创建失败')),
        );
      }
      return;
    }

    // 进度状态
    int received = 0;
    int total = obj.size > 0 ? obj.size : 1;
    double progress = 0.0;
    // 捕获 StatefulBuilder 的 setState，用于更新对话框进度
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('下载失败：保存文件失败')),
            );
          }
        }
      } else {
        logError('Download failed: ${downloadResult.errorMessage}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载失败: ${downloadResult.errorMessage}')),
          );
        }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：未找到凭证')),
        );
      }
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：API创建失败')),
        );
      }
      return;
    }

    logUi('Starting delete: ${obj.key}');
    final result = await api.deleteObject(
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      objectKey: obj.key,
    );

    if (mounted) {
      if (result.success) {
        logUi('Delete successful: ${obj.name}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除成功: ${obj.name}')),
        );
        // 刷新文件列表
        _loadObjects();
      } else {
        logError('Delete failed: ${result.errorMessage}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: ${result.errorMessage}')),
        );
      }
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
      final objectKey = pickedFile.name;

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
      _loadObjects();
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

    // 逐个删除文件
    for (final obj in selectedFiles) {
      logUi('Deleting: ${obj.name}');
      final result = await api.deleteObject(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        objectKey: obj.key,
      );

      if (result.success) {
        successCount++;
        logUi('Deleted: ${obj.name}');
      } else {
        failCount++;
        logError('Delete failed: ${obj.name}, ${result.errorMessage}');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功删除 $successCount 个文件${failCount > 0 ? '，$failCount 个失败' : ''}')),
      );
      // 刷新文件列表并退出选择模式
      _loadObjects();
      _exitSelectionMode();
    }
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

  /// 格式化字节大小
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
