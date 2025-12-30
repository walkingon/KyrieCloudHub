import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/transfer_task.dart';
import '../../services/transfer_queue_service.dart';

class TransferQueueScreen extends StatefulWidget {
  const TransferQueueScreen({super.key});

  @override
  State<TransferQueueScreen> createState() => _TransferQueueScreenState();
}

class _TransferQueueScreenState extends State<TransferQueueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TransferQueueService _transferQueueService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _transferQueueService = Provider.of<TransferQueueService>(context, listen: false);
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
          tabs: [
            Tab(text: '进行中'),
            Tab(text: '已完成'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'clear_completed':
                  _transferQueueService.clearCompleted();
                  break;
                case 'clear_failed':
                  _transferQueueService.clearFailed();
                  break;
                case 'clear_all':
                  _showClearAllDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'clear_completed', child: Text('清空已完成')),
              const PopupMenuItem(value: 'clear_failed', child: Text('清空失败')),
              const PopupMenuItem(value: 'clear_all', child: Text('清空全部')),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInProgressTab(),
          _buildCompletedTab(),
        ],
      ),
    );
  }

  Widget _buildInProgressTab() {
    return Consumer<TransferQueueService>(
      builder: (context, service, child) {
        final inProgressTasks = service.inProgressQueue;
        final pendingTasks = service.pendingQueue;

        if (inProgressTasks.isEmpty && pendingTasks.isEmpty) {
          return const Center(
            child: Text('暂无传输任务'),
          );
        }

        return ListView(
          children: [
            if (pendingTasks.isNotEmpty) ...[
              _buildSectionHeader('等待中 (${pendingTasks.length})'),
              ...pendingTasks.map((task) => _buildPendingTaskItem(task)),
            ],
            if (inProgressTasks.isNotEmpty) ...[
              _buildSectionHeader('传输中 (${inProgressTasks.length})'),
              ...inProgressTasks.map((task) => _buildInProgressTaskItem(task)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCompletedTab() {
    return Consumer<TransferQueueService>(
      builder: (context, service, child) {
        final completedTasks = service.completedQueue;
        final failedTasks = service.failedQueue;

        if (completedTasks.isEmpty && failedTasks.isEmpty) {
          return const Center(
            child: Text('暂无已完成的任务'),
          );
        }

        return ListView(
          children: [
            if (completedTasks.isNotEmpty) ...[
              _buildSectionHeader('已完成 (${completedTasks.length})'),
              ...completedTasks.map((task) => _buildCompletedTaskItem(task)),
            ],
            if (failedTasks.isNotEmpty) ...[
              _buildSectionHeader('失败 (${failedTasks.length})'),
              ...failedTasks.map((task) => _buildFailedTaskItem(task)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildPendingTaskItem(TransferTask task) {
    return ListTile(
      leading: Icon(
        task.type == TransferType.upload ? Icons.upload : Icons.download,
        color: Colors.orange,
      ),
      title: Text(task.fileName),
      subtitle: Text(task.type == TransferType.upload ? '等待上传' : '等待下载'),
      trailing: IconButton(
        icon: const Icon(Icons.close, color: Colors.grey),
        onPressed: () => _transferQueueService.cancelTask(task.id),
      ),
    );
  }

  Widget _buildInProgressTaskItem(TransferTask task) {
    return ListTile(
      leading: Icon(
        task.type == TransferType.upload ? Icons.upload : Icons.download,
        color: Colors.blue,
      ),
      title: Text(task.fileName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.type == TransferType.upload ? '上传中' : '下载中'),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: task.progress,
            minHeight: 4,
          ),
          const SizedBox(height: 2),
          Text(
            '${_formatSize(task.transferredSize)} / ${_formatSize(task.totalSize)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.pause, color: Colors.orange),
            onPressed: () => _transferQueueService.pauseTask(task.id),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _showCancelDialog(task),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedTaskItem(TransferTask task) {
    return ListTile(
      leading: const Icon(Icons.check_circle, color: Colors.green),
      title: Text(task.fileName),
      subtitle: Text(
        task.endTime != null
            ? '${task.type == TransferType.upload ? "上传" : "下载"}完成 ${_formatTime(task.endTime!)}'
            : '已完成',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, color: Colors.grey),
        onPressed: () => _transferQueueService.removeCompletedTask(task.id),
      ),
    );
  }

  Widget _buildFailedTaskItem(TransferTask task) {
    return ListTile(
      leading: const Icon(Icons.error, color: Colors.red),
      title: Text(task.fileName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.errorMessage ?? '传输失败',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => _transferQueueService.resumeTask(task.id),
                child: const Text('重试'),
              ),
              const SizedBox(width: 16),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => _transferQueueService.removeFailedTask(task.id),
                child: const Text('移除'),
              ),
            ],
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

  void _showCancelDialog(TransferTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消传输'),
        content: Text('确定要取消传输 "${task.fileName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('否'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _transferQueueService.cancelTask(task.id);
            },
            child: const Text('是'),
          ),
        ],
      ),
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空队列'),
        content: const Text('确定要清空所有传输任务吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('否'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _transferQueueService.clearAll();
            },
            child: const Text('是'),
          ),
        ],
      ),
    );
  }
}
