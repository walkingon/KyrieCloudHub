import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:file_picker/file_picker.dart';
import '../services/storage_service.dart';
import '../utils/file_path_helper.dart';
import '../utils/logger.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storage = StorageService();
  String _downloadDirectory = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloadDirectory();
  }

  Future<void> _loadDownloadDirectory() async {
    final directory = await _storage.getDownloadDirectory();
    setState(() {
      _downloadDirectory = directory ?? '';
      _isLoading = false;
    });
  }

  /// 获取当前显示的下载根目录（带 FilePathHelper.kDownloadSubDir 后缀）
  String get _displayDownloadRoot {
    if (_downloadDirectory.isEmpty) {
      // 返回默认目录（使用缓存值）
      final defaultDir = FilePathHelper.systemDownloadsDirectory ?? '';
      return '$defaultDir/${FilePathHelper.kDownloadSubDir}/';
    }
    return '$_downloadDirectory/${FilePathHelper.kDownloadSubDir}/';
  }

  Future<void> _selectDownloadDirectory() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载目录',
    );

    if (directoryPath == null || directoryPath.isEmpty) {
      logUi('User cancelled directory selection');
      return;
    }

    // 检查目录是否有写入权限
    try {
      final testFile = File('$directoryPath/.write_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      logUi('Directory has write permission: $directoryPath');
    } catch (e) {
      logError('Directory lacks write permission: $directoryPath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('选择的目录没有写入权限，请选择其他目录'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await _storage.saveDownloadDirectory(directoryPath);
    setState(() {
      _downloadDirectory = directoryPath;
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载目录已设置为: $directoryPath')));
    }
  }

  Future<void> _resetToDefaultDirectory() async {
    final defaultDirectory = await getDownloadsDirectory();
    await _storage.saveDownloadDirectory(defaultDirectory);
    setState(() {
      _downloadDirectory = defaultDirectory;
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已重置为默认下载目录: $defaultDirectory')));
    }
  }

  Future<String> getDownloadsDirectory() async {
    // 尝试获取系统下载目录（使用缓存值）
    final downloads = getDownloadsDirectoryPath();
    if (downloads != null && downloads.isNotEmpty) {
      return downloads;
    }

    // 如果获取不到，返回应用数据目录下的默认路径
    final directory = await path_provider.getApplicationSupportDirectory();
    return directory.path;
  }

  // 辅助方法：获取系统下载目录路径（使用缓存值）
  String? getDownloadsDirectoryPath() {
    return FilePathHelper.systemDownloadsDirectory;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildDownloadDirectorySection(),
                const SizedBox(height: 24),
                _buildInfoSection(),
              ],
            ),
    );
  }

  Widget _buildDownloadDirectorySection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.download, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '下载设置',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '下载目录',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _displayDownloadRoot,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '文件存储路径: ${FilePathHelper.kDownloadSubDir}/平台名/存储桶名/文件对象键',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _selectDownloadDirectory,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择目录'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _resetToDefaultDirectory,
                  icon: const Icon(Icons.refresh),
                  label: const Text('默认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '说明',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '1. 默认下载目录为系统下载目录下的 "KyrieCloudHubDownload" 文件夹\n'
              '2. 修改下载目录后，下载的文件将保存到新目录下\n'
              '3. 已下载的文件会有标识显示\n'
              '4. 如果文件已存在，系统将提示并不再重复下载',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
