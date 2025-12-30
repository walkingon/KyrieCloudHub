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
      appBar: AppBar(title: Text(widget.bucket.name)),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _objects.length,
              itemBuilder: (context, index) {
                final obj = _objects[index];
                return ListTile(
                  leading: Icon(
                    obj.type == ObjectType.file
                        ? Icons.insert_drive_file
                        : Icons.folder,
                  ),
                  title: Text(obj.name),
                  subtitle: Text(obj.lastModified?.toString() ?? ''),
                  onTap: () {
                    // 显示操作选项
                    logUi('User tapped object: ${obj.name}');
                    _showObjectActions(obj);
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadFile,
        child: Icon(Icons.add),
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

    final pickedFile = result.files.first;
    logUi('Selected file: ${pickedFile.name}, size: ${pickedFile.size} bytes');

    if (!mounted) return;

    // 读取文件内容
    final fileBytes = await _readFileBytes(pickedFile);
    if (fileBytes == null) {
      logError('Failed to read file bytes');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取文件失败')),
        );
      }
      return;
    }

    // 构建上传路径
    final objectKey = pickedFile.name;

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

    // 进度状态
    int sent = 0;
    int total = fileBytes.length;
    double progress = 0.0;

    // 显示上传进度对话框（不阻塞上传）
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('上传中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在上传: ${pickedFile.name}', maxLines: 2),
                  SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: progress,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('${(progress * 100).toInt()}% (${_formatBytes(sent)} / ${_formatBytes(total)})'),
                ],
              ),
            );
          },
        );
      },
    );

    // 执行上传（非阻塞）
    logUi('Starting upload: $objectKey');
    unawaited(api.uploadObject(
      bucketName: widget.bucket.name,
      region: widget.bucket.region,
      objectKey: objectKey,
      data: fileBytes,
      onProgress: (s, t) {
        if (!mounted) return;
        setState(() {
          sent = s;
          total = t;
          progress = t > 0 ? s / t : 0.0;
        });
      },
    ).then((result) {
      if (mounted) {
        // 关闭进度对话框
        Navigator.of(context).pop();

        if (result.success) {
          logUi('Upload successful: $objectKey');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传成功: ${pickedFile.name}')),
          );
          // 刷新文件列表
          _loadObjects();
        } else {
          logError('Upload failed: ${result.errorMessage}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传失败: ${result.errorMessage}')),
          );
        }
      }
    }));
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
