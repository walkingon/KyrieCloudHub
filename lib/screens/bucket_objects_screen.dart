import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/bucket.dart';
import '../models/object_file.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
import '../services/transfer_queue_service.dart';
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
  bool _selectionMode = false;
  final Set<String> _selectedObjects = {};
  late final StorageService _storage;
  late final CloudPlatformFactory _factory;
  late final TransferQueueService _transferService;

  @override
  void initState() {
    super.initState();
    logUi('BucketObjectsScreen initialized for bucket: ${widget.bucket.name}');
    _storage = Provider.of<StorageService>(context, listen: false);
    _factory = Provider.of<CloudPlatformFactory>(context, listen: false);
    _transferService = TransferQueueService();
    _loadObjects();
  }

  void _toggleSelectionMode() {
    setState(() {
      if (_selectionMode) {
        _selectionMode = false;
        _selectedObjects.clear();
      } else {
        _selectionMode = true;
      }
    });
  }

  void _toggleObjectSelection(String objectKey) {
    setState(() {
      if (_selectedObjects.contains(objectKey)) {
        _selectedObjects.remove(objectKey);
        if (_selectedObjects.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedObjects.add(objectKey);
      }
    });
  }

  bool _isObjectSelected(String objectKey) => _selectedObjects.contains(objectKey);

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
        title: Text(widget.bucket.name),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: Icon(Icons.select_all),
                  onPressed: () {
                    if (_selectedObjects.length == _objects.length) {
                      _selectedObjects.clear();
                    } else {
                      _selectedObjects.clear();
                      _selectedObjects.addAll(_objects.map((o) => o.key));
                    }
                    setState(() {});
                  },
                  tooltip: '全选',
                ),
                IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: _selectedObjects.isNotEmpty ? _batchDelete : null,
                  tooltip: '批量删除',
                ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: _toggleSelectionMode,
                  tooltip: '取消选择',
                ),
              ]
            : null,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _objects.length,
              itemBuilder: (context, index) {
                final obj = _objects[index];
                final isSelected = _isObjectSelected(obj.key);

                return ListTile(
                  leading: _selectionMode
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleObjectSelection(obj.key),
                        )
                      : Icon(
                          obj.type == ObjectType.file
                              ? Icons.insert_drive_file
                              : Icons.folder,
                        ),
                  title: Text(obj.name),
                  subtitle: Text(obj.lastModified?.toString() ?? ''),
                  selected: isSelected,
                  selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                  onTap: () {
                    if (_selectionMode) {
                      _toggleObjectSelection(obj.key);
                    } else {
                      // 显示操作选项
                      logUi('User tapped object: ${obj.name}');
                      _showObjectActions(obj);
                    }
                  },
                  onLongPress: () {
                    if (!_selectionMode) {
                      _toggleSelectionMode();
                      _toggleObjectSelection(obj.key);
                    }
                  },
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_selectionMode && _selectedObjects.isNotEmpty)
            FloatingActionButton(
              heroTag: 'batchDownload',
              mini: true,
              tooltip: '批量下载',
              onPressed: _batchDownload,
              child: Icon(Icons.download),
            ),
          FloatingActionButton(
            heroTag: 'upload',
            tooltip: '上传文件',
            onPressed: _uploadFile,
            child: Icon(Icons.add),
          ),
        ],
      ),
    );
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

    // 显示下载进度对话框（不阻塞下载）
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
        if (!mounted) return;
        setState(() {
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

  Future<void> _uploadFile() async {
    logUi('User tapped upload button');

    // 弹出文件选择器
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      logUi('User cancelled file selection');
      return;
    }
  }

  /// 批量删除
  Future<void> _batchDelete() async {
    if (_selectedObjects.isEmpty) return;

    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 ${_selectedObjects.length} 个文件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 获取凭证并创建API
    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      logError('No credential found for platform: ${widget.platform}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败：未找到凭证')),
        );
      }
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      return;
    }

    final selectedKeys = _selectedObjects.toList();
    int successCount = 0;
    int failCount = 0;

    for (final key in selectedKeys) {
      final result = await api.deleteObject(
        bucketName: widget.bucket.name,
        region: widget.bucket.region,
        objectKey: key,
      );

      if (result.success) {
        successCount++;
      } else {
        failCount++;
      }
    }

    // 清除选择模式并刷新
    _toggleSelectionMode();
    _loadObjects();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除完成：成功 $successCount 个，失败 $failCount 个'),
        ),
      );
    }
  }

  /// 批量下载
  Future<void> _batchDownload() async {
    if (_selectedObjects.isEmpty) return;

    final selectedFiles = _objects.where((o) => _selectedObjects.contains(o.key)).toList();

    // 获取凭证并创建API
    final credential = await _storage.getCredential(widget.platform);
    if (credential == null) {
      logError('No credential found for platform: ${widget.platform}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败：未找到凭证')),
        );
      }
      return;
    }

    final api = _factory.createApi(widget.platform, credential: credential);
    if (api == null) {
      logError('Failed to create API for platform: ${widget.platform}');
      return;
    }

    // 设置TransferQueueService的API
    _transferService.setApi(api);

    // 添加每个文件到下载队列
    for (final obj in selectedFiles) {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: obj.name,
      );

      if (savePath == null || savePath.isEmpty) {
        continue;
      }

      await _transferService.addDownloadTask(
        fileName: obj.name,
        savePath: savePath,
        bucketName: widget.bucket.name,
        objectKey: obj.key,
        fileSize: obj.size,
        region: widget.bucket.region,
      );
    }

    // 清除选择模式
    _toggleSelectionMode();

    // 提示用户查看传输队列
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已将 ${selectedFiles.length} 个文件加入下载队列'),
          action: SnackBarAction(
            label: '查看队列',
            onPressed: () {
              // 导航到传输队列页面
              Navigator.pushNamed(context, '/transfer-queue');
            },
          ),
        ),
      );
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
