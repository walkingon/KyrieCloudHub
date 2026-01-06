import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../models/object_file.dart';
import '../../../../models/platform_type.dart';
import '../../../../services/api/cloud_platform_api.dart';
import '../../../../services/storage_service.dart';
import '../../../../utils/logger.dart';

/// 批量操作处理器
class BatchOperations {
  /// 批量删除
  static Future<void> batchDelete({
    required BuildContext context,
    required List<ObjectFile> selectedFiles,
    required ICloudPlatformApi api,
    required String bucketName,
    required String region,
    required VoidCallback onSuccess,
    required void Function(String error) onError,
  }) async {
    if (selectedFiles.isEmpty) return;

    logUi('Batch delete: ${selectedFiles.length} files');

    int successCount = 0;
    int failCount = 0;

    // 批量删除文件
    final objectKeys = selectedFiles.map((obj) => obj.key).toList();
    logUi('Deleting: ${objectKeys.length} objects in batch');
    final result = await api.deleteObjects(
      bucketName: bucketName,
      region: region,
      objectKeys: objectKeys,
    );

    if (result.success) {
      successCount = objectKeys.length;
      logUi('Batch delete completed: $successCount objects');
    } else {
      failCount = objectKeys.length;
      logError('Batch delete failed: ${result.errorMessage}');
      onError(result.errorMessage ?? '批量删除失败');
      return;
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '成功删除 $successCount 个文件${failCount > 0 ? '，$failCount 个失败' : ''}',
        ),
      ),
    );

    // 等待一段时间后再刷新（腾讯云COS使用最终一致性模型）
    await Future.delayed(const Duration(milliseconds: 500));
    if (!context.mounted) return;

    onSuccess();
  }

  /// 批量下载
  static Future<void> batchDownload({
    required BuildContext context,
    required List<ObjectFile> selectedFiles,
    required ICloudPlatformApi api,
    required String bucketName,
    required String region,
    required String downloadDirectory,
    required PlatformType platform,
    required StorageService storage,
    required Set<String> downloadedFileKeys,
    required VoidCallback onComplete,
    required void Function(String error) onError,
  }) async {
    if (selectedFiles.isEmpty) return;

    logUi('Batch download: ${selectedFiles.length} files');

    int successCount = 0;
    int skipCount = 0;
    int failCount = 0;

    // 显示进度对话框
    int currentIndex = 0;
    String currentFile = '';

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('批量下载中'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('正在下载: $currentFile', maxLines: 2),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: currentIndex / selectedFiles.length,
                    ),
                  ),
                  const SizedBox(height: 8),
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

      // 构建保存路径
      final relativePath = obj.key.split('/').where((e) => e.isNotEmpty).join('/');
      final savePath = '$downloadDirectory/$relativePath';
      final saveFile = File(savePath);
      saveFile.parent.createSync(recursive: true);

      // 检查文件是否已存在
      if (await saveFile.exists()) {
        logUi('File already exists, skipping: $savePath');
        skipCount++;
        continue;
      }

      // 检查是否已记录为已下载
      if (downloadedFileKeys.contains(obj.key)) {
        logUi('File already in download record: ${obj.key}');
        skipCount++;
        continue;
      }

      logUi('Downloading: ${obj.name} to $savePath');

      // 根据文件大小选择下载方式
      final fileSize = obj.size;
      const largeFileThreshold = 100 * 1024 * 1024; // 100MB
      final isLargeFile = fileSize > largeFileThreshold;

      logUi(
          'Batch downloading: ${obj.key}, size: $fileSize bytes, mode: ${isLargeFile ? 'multipart' : 'normal'}');

      ApiResponse<void> result;
      if (isLargeFile) {
        // 大文件使用分块下载
        result = await api.downloadObjectMultipart(
          bucketName: bucketName,
          region: region,
          objectKey: obj.key,
          outputFile: saveFile,
          chunkSize: 64 * 1024 * 1024, // 64MB 分块
          onProgress: (r, t) {},
        );
      } else {
        // 小文件使用普通下载
        result = await api.downloadObject(
          bucketName: bucketName,
          region: region,
          objectKey: obj.key,
          outputFile: saveFile,
          onProgress: (r, t) {},
        );
      }

      if (result.success) {
        successCount++;
        // 记录到已下载文件列表
        await storage.addDownloadedFile(
          platform.value,
          bucketName,
          obj.key,
          savePath,
        );
        logUi('Downloaded: ${obj.name} -> $savePath');
      } else {
        failCount++;
        logError('Download failed: ${obj.name}, ${result.errorMessage}');
      }
    }

    // 关闭进度对话框并显示结果
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '成功下载 $successCount 个文件${skipCount > 0 ? '，跳过 $skipCount 个已存在' : ''}${failCount > 0 ? '，失败 $failCount 个' : ''}',
          ),
        ),
      );
      onComplete();
    }
  }
}
