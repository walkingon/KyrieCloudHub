import 'package:flutter/material.dart';

/// 通用进度对话框工具类
class ProgressDialog {
  /// 显示简单进度对话框
  ///
  /// [context] BuildContext
  /// [title] 对话框标题
  /// [message] 显示的消息
  /// [progress] 进度值 (0.0-1.0)，传null时显示不确定进度条
  /// [current] 当前数量（与total配合显示 "current/total"）
  /// [total] 总数量
  /// [dismissible] 是否可取消
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String message = '',
    double? progress,
    int current = 0,
    int total = 0,
    bool cancellable = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: cancellable,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isNotEmpty)
              Text(message, maxLines: 2),
            if (message.isNotEmpty) const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: progress != null
                  ? LinearProgressIndicator(value: progress)
                  : const LinearProgressIndicator(),
            ),
            if (total > 0) const SizedBox(height: 8),
            if (total > 0)
              Text('$current/$total'),
            if (progress != null && total == 0)
              Text('${(progress * 100).toInt()}%'),
          ],
        ),
      ),
    );
  }

  /// 显示下载进度对话框
  static Future<void> showDownload({
    required BuildContext context,
    required String fileName,
    required int received,
    required int total,
    ValueChanged<int>? onCancel,
  }) {
    final progress = total > 0 ? received / total : 0.0;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('下载中'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('正在下载: $fileName', maxLines: 2),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(value: progress),
              ),
              const SizedBox(height: 8),
              Text('${(progress * 100).toInt()}% (${_formatBytes(received)} / ${_formatBytes(total)})'),
            ],
          ),
          actions: [
            if (onCancel != null)
              TextButton(
                onPressed: () {
                  onCancel(received);
                  Navigator.of(context).pop();
                },
                child: const Text('取消'),
              ),
          ],
        ),
      ),
    );
  }

  /// 显示上传进度对话框
  static Future<void> showUpload({
    required BuildContext context,
    required String fileName,
    required int currentIndex,
    required int total,
    required double progress,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('上传文件中'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('正在上传: $fileName', maxLines: 2),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(value: progress),
            ),
            const SizedBox(height: 8),
            Text('${(progress * 100).toInt()}%'),
            const SizedBox(height: 8),
            Text('$currentIndex/$total'),
          ],
        ),
      ),
    );
  }

  /// 显示批量操作进度对话框
  static Future<void> showBatchOperation({
    required BuildContext context,
    required String title,
    required String currentFile,
    required int currentIndex,
    required int total,
    String operation = '',
  }) {
    final progress = total > 0 ? currentIndex / total : 0.0;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('正在处理: $currentFile', maxLines: 2),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(value: progress),
            ),
            const SizedBox(height: 8),
            Text('$currentIndex/$total'),
          ],
        ),
      ),
    );
  }

  /// 显示文件夹下载/扫描进度对话框
  static Future<void> showFolderOperation({
    required BuildContext context,
    required String message,
    required int current,
    required int total,
  }) {
    final progress = total > 0 ? current / total : 0.0;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('下载中'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, maxLines: 2),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(value: progress),
            ),
            const SizedBox(height: 8),
            Text('$current / $total'),
          ],
        ),
      ),
    );
  }

  /// 格式化字节大小
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
