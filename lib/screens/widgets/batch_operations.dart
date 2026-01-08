import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../models/object_file.dart';
import '../../../../services/api/cloud_platform_api.dart';
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

  /// 格式化字节大小
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 批量下载
  static Future<void> batchDownload({
    required BuildContext context,
    required List<ObjectFile> selectedFiles,
    required ICloudPlatformApi api,
    required String bucketName,
    required String region,
    required String downloadDirectory,
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
    int currentFileReceived = 0;
    int currentFileTotal = 0;

    // 用于更新进度对话框的回调
    void Function(VoidCallback fn)? setDialogState;

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            setDialogState = setState;
            // 当前文件的进度
            final fileProgress = currentFileTotal > 0 ? currentFileReceived / currentFileTotal : 0.0;
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
                      value: fileProgress,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${_formatBytes(currentFileReceived)} / ${_formatBytes(currentFileTotal)} (${(fileProgress * 100).toInt()}%)'),
                  const SizedBox(height: 4),
                  Text('$currentIndex/${selectedFiles.length}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            );
          },
        );
      },
    );

    // 进度更新函数
    void updateProgress(int received) {
      if (setDialogState != null) {
        setDialogState!(() {
          currentFileReceived = received;
        });
      }
    }

    // 逐个下载文件
    for (final obj in selectedFiles) {
      currentFile = obj.name;
      currentFileReceived = 0;
      currentFileTotal = obj.size;
      currentIndex++; // 先增加索引，表示正在处理第几个文件

      // 更新UI显示新文件信息
      if (setDialogState != null) {
        setDialogState!(() {});
      }

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
          chunkSize: kDefaultChunkSize, // 使用默认分块大小
          onProgress: (received, total) {
            currentFileTotal = total > 0 ? total : obj.size;
            updateProgress(received);
          },
        );
      } else {
        // 小文件使用普通下载
        result = await api.downloadObject(
          bucketName: bucketName,
          region: region,
          objectKey: obj.key,
          outputFile: saveFile,
          onProgress: (received, total) {
            currentFileTotal = total > 0 ? total : obj.size;
            updateProgress(received);
          },
        );
      }

      if (result.success) {
        successCount++;
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
