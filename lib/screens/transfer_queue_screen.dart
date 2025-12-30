import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/transfer_queue_service.dart';
import '../models/transfer_task.dart';

// ignore_for_file: library_private_types_in_public_api

class TransferQueueScreen extends StatefulWidget {
  const TransferQueueScreen({super.key});

  @override
  _TransferQueueScreenState createState() => _TransferQueueScreenState();
}

class _TransferQueueScreenState extends State<TransferQueueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TransferQueueService _transferService = TransferQueueService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _transferService.restoreTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('传输队列'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '进行中'),
            Tab(text: '已完成'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearDialog(context),
            tooltip: '清理已完成的任务',
          ),
        ],
      ),
      body: ChangeNotifierProvider.value(
        value: _transferService,
        child: Consumer<TransferQueueService>(
          builder: (context, service, child) {
            final inProgressTasks = service.allTasks
                .where((t) => t.isInProgress || t.status == TransferStatus.pending || t.status == TransferStatus.paused)
                .toList()
              ..sort((a, b) => a.startTime?.compareTo(b.startTime ?? DateTime.now()) ?? 0);

            final completedTasks = service.allTasks
                .where((t) => t.isCompleted || t.isFailed || t.isCancelled)
                .toList()
              ..sort((a, b) => b.endTime?.compareTo(a.endTime ?? DateTime.now()) ?? 0);

            return TabBarView(
              controller: _tabController,
              children: [
                // 进行中
                inProgressTasks.isEmpty
                    ? _buildEmptyState('暂无进行中的传输任务')
                    : ListView.builder(
                        itemCount: inProgressTasks.length,
                        itemBuilder: (context, index) =>
                            _buildInProgressTaskTile(inProgressTasks[index], service),
                      ),
                // 已完成
                completedTasks.isEmpty
                    ? _buildEmptyState('暂无已完成的传输任务')
                    : ListView.builder(
                        itemCount: completedTasks.length,
                        itemBuilder: (context, index) =>
                            _buildCompletedTaskTile(completedTasks[index], service),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_queue,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInProgressTaskTile(TransferTask task, TransferQueueService service) {
    final isPaused = task.status == TransferStatus.paused;
    final isPending = task.status == TransferStatus.pending;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _buildTaskIcon(task),
        title: Text(
          task.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isPaused
                      ? '已暂停'
                      : isPending
                          ? '等待中'
                          : '${_formatSize(task.transferredSize)} / ${_formatSize(task.totalSize)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPaused ? Colors.orange : Colors.grey[600],
                  ),
                ),
                Text(
                  task.type == TransferType.upload ? '上传' : '下载',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPaused)
              IconButton(
                icon: const Icon(Icons.play_arrow, color: Colors.green),
                onPressed: () => service.resumeTask(task.id),
                tooltip: '继续',
              )
            else if (!isPending)
              IconButton(
                icon: const Icon(Icons.pause, color: Colors.orange),
                onPressed: () => service.pauseTask(task.id),
                tooltip: '暂停',
              ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () => _showCancelDialog(context, task, service),
              tooltip: '取消',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedTaskTile(TransferTask task, TransferQueueService service) {
    final isFailed = task.isFailed;
    final isCancelled = task.isCancelled;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _buildTaskIcon(task),
        title: Text(
          task.fileName,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isFailed ? Colors.red : isCancelled ? Colors.grey : Colors.green,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              isFailed
                  ? '失败: ${task.errorMessage ?? "未知错误"}'
                  : isCancelled
                      ? '已取消'
                      : '已完成 - ${_formatSize(task.totalSize)}',
              style: TextStyle(
                fontSize: 12,
                color: isFailed ? Colors.red : isCancelled ? Colors.grey : Colors.green,
              ),
            ),
            if (task.endTime != null)
              Text(
                _formatTime(task.endTime!),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFailed)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.blue),
                onPressed: () => service.retryTask(task.id),
                tooltip: '重试',
              ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.grey),
              onPressed: () => service.removeTask(task.id),
              tooltip: '删除',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskIcon(TransferTask task) {
    IconData icon;
    Color color;

    if (task.type == TransferType.upload) {
      icon = Icons.upload;
      color = Colors.blue;
    } else {
      icon = Icons.download;
      color = Colors.green;
    }

    if (task.isPaused) {
      color = Colors.orange;
    } else if (task.isFailed) {
      color = Colors.red;
    } else if (task.isCancelled) {
      color = Colors.grey;
    }

    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _showCancelDialog(BuildContext context, TransferTask task, TransferQueueService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消传输'),
        content: Text('确定要取消传输 "${task.fileName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              service.cancelTask(task.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理已完成任务'),
        content: const Text('确定要删除所有已完成的传输记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _transferService.cleanupOldTasks(keepCount: 0);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
