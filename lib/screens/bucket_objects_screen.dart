import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bucket.dart';
import '../models/object_file.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';

class BucketObjectsScreen extends StatefulWidget {
  final Bucket bucket;
  final PlatformType platform;

  BucketObjectsScreen({required this.bucket, required this.platform});

  @override
  _BucketObjectsScreenState createState() => _BucketObjectsScreenState();
}

class _BucketObjectsScreenState extends State<BucketObjectsScreen> {
  List<ObjectFile> _objects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadObjects();
  }

  Future<void> _loadObjects() async {
    setState(() {
      _isLoading = true;
    });

    final storage = Provider.of<StorageService>(context, listen: false);
    final credential = await storage.getCredential(widget.platform);
    if (credential != null) {
      final factory = Provider.of<CloudPlatformFactory>(context, listen: false);
      final api = factory.createApi(widget.platform, credential: credential);
      if (api != null) {
        final result = await api.listObjects(
          bucketName: widget.bucket.name,
          region: widget.bucket.region,
        );
        if (result.success) {
          setState(() {
            _objects = result.data?.objects ?? [];
          });
        }
      }
    }

    setState(() {
      _isLoading = false;
    });
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
                _downloadObject(obj);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete),
              title: Text('删除'),
              onTap: () {
                Navigator.pop(context);
                _deleteObject(obj);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadObject(ObjectFile obj) async {
    // 实现下载逻辑
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('下载功能待实现')));
  }

  Future<void> _deleteObject(ObjectFile obj) async {
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
      // 实现删除逻辑
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除功能待实现')));
    }
  }

  Future<void> _uploadFile() async {
    // 实现上传逻辑
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('上传功能待实现')));
  }
}
