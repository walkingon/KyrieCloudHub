import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('下载功能待实现')));
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
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      logUi('User confirmed delete: ${obj.name}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除功能待实现')));
      }
    } else {
      logUi('User cancelled delete: ${obj.name}');
    }
  }

  Future<void> _uploadFile() async {
    logUi('User tapped upload button');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('上传功能待实现')));
    }
  }
}
