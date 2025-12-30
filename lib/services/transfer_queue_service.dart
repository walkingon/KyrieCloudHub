import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/transfer_task.dart';
import '../utils/logger.dart';

/// 传输队列服务
/// 管理所有传输任务的队列、并发控制和状态追踪
class TransferQueueService extends ChangeNotifier {
  // 单例模式
  static final TransferQueueService _instance = TransferQueueService._internal();
  factory TransferQueueService() => _instance;
  TransferQueueService._internal();

  // 任务队列
  final List<TransferTask> _pendingQueue = [];
  final List<TransferTask> _inProgressQueue = [];
  final List<TransferTask> _completedQueue = [];
  final List<TransferTask> _failedQueue = [];

  // 并发控制
  int _maxConcurrentTasks = 2;
  int get maxConcurrentTasks => _maxConcurrentTasks;
  final List<StreamSubscription> _activeSubscriptions = [];

  // 状态流
  final StreamController<TransferTask> _taskUpdateController = StreamController<TransferTask>.broadcast();
  Stream<TransferTask> get taskUpdates => _taskUpdateController.stream;

  // 获取队列
  UnmodifiableListView<TransferTask> get pendingQueue => UnmodifiableListView(_pendingQueue);
  UnmodifiableListView<TransferTask> get inProgressQueue => UnmodifiableListView(_inProgressQueue);
  UnmodifiableListView<TransferTask> get completedQueue => UnmodifiableListView(_completedQueue);
  UnmodifiableListView<TransferTask> get failedQueue => UnmodifiableListView(_failedQueue);

  // 获取所有任务
  List<TransferTask> get allTasks {
    final all = [..._pendingQueue, ..._inProgressQueue, ..._completedQueue, ..._failedQueue];
    return all;
  }

  // 设置最大并发数
  void setMaxConcurrentTasks(int max) {
    if (max > 0 && max <= 5) {
      _maxConcurrentTasks = max;
      logger.info('最大并发任务数设置为: $max');
      _processQueue();
    }
  }

  /// 添加上传任务
  String addUploadTask({
    required String fileName,
    required String filePath,
    required String bucketName,
    required String objectKey,
    required int totalSize,
  }) {
    final task = TransferTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: fileName,
      filePath: filePath,
      bucketName: bucketName,
      objectKey: objectKey,
      type: TransferType.upload,
      totalSize: totalSize,
      status: TransferStatus.pending,
    );

    _pendingQueue.add(task);
    logger.info('添加上传任务: $fileName');
    notifyListeners();
    _processQueue();

    return task.id;
  }

  /// 添加下载任务
  String addDownloadTask({
    required String fileName,
    required String filePath,
    required String bucketName,
    required String objectKey,
    required int totalSize,
  }) {
    final task = TransferTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: fileName,
      filePath: filePath,
      bucketName: bucketName,
      objectKey: objectKey,
      type: TransferType.download,
      totalSize: totalSize,
      status: TransferStatus.pending,
    );

    _pendingQueue.add(task);
    logger.info('添加下载任务: $fileName');
    notifyListeners();
    _processQueue();

    return task.id;
  }

  /// 处理队列
  void _processQueue() {
    while (_inProgressQueue.length < _maxConcurrentTasks && _pendingQueue.isNotEmpty) {
      final task = _pendingQueue.removeAt(0);
      _startTask(task);
    }
  }

  /// 开始执行任务
  void _startTask(TransferTask task) {
    task.status = TransferStatus.inProgress;
    task.startTime = DateTime.now();
    _inProgressQueue.add(task);

    logger.info('开始执行任务: ${task.fileName} (${task.type.name})');
    notifyListeners();
    _taskUpdateController.add(task);
  }

  /// 更新任务进度
  void updateProgress(String taskId, int transferredSize, {String? errorMessage}) {
    final task = _findTask(taskId);
    if (task != null) {
      task.transferredSize = transferredSize;
      if (errorMessage != null) {
        task.errorMessage = errorMessage;
      }
      notifyListeners();
      _taskUpdateController.add(task);
    }
  }

  /// 标记任务完成
  void completeTask(String taskId) {
    final task = _findTask(taskId);
    if (task != null) {
      task.status = TransferStatus.completed;
      task.endTime = DateTime.now();
      task.transferredSize = task.totalSize;

      _moveToCompleted(task);
      logger.info('任务完成: ${task.fileName}');
      notifyListeners();
      _taskUpdateController.add(task);
      _processQueue();
    }
  }

  /// 标记任务失败
  void failTask(String taskId, String errorMessage) {
    final task = _findTask(taskId);
    if (task != null) {
      task.status = TransferStatus.failed;
      task.endTime = DateTime.now();
      task.errorMessage = errorMessage;

      _inProgressQueue.remove(task);
      _failedQueue.add(task);
      logger.warning('任务失败: ${task.fileName} - $errorMessage');
      notifyListeners();
      _taskUpdateController.add(task);
      _processQueue();
    }
  }

  /// 暂停任务
  void pauseTask(String taskId) {
    final task = _findTask(taskId);
    if (task != null && task.status == TransferStatus.inProgress) {
      task.status = TransferStatus.paused;
      _inProgressQueue.remove(task);
      _pendingQueue.insert(0, task);
      logger.info('任务已暂停: ${task.fileName}');
      notifyListeners();
      _processQueue();
    }
  }

  /// 恢复任务
  void resumeTask(String taskId) {
    final task = _findTaskInPending(taskId);
    if (task != null) {
      _pendingQueue.remove(task);
      _startTask(task);
      logger.info('任务已恢复: ${task.fileName}');
    }
  }

  /// 取消任务
  void cancelTask(String taskId) {
    final inProgressTask = _findTaskInProgress(taskId);
    final pendingTask = _findTaskInPending(taskId);

    if (inProgressTask != null) {
      inProgressTask.status = TransferStatus.cancelled;
      inProgressTask.endTime = DateTime.now();
      _inProgressQueue.remove(inProgressTask);
      logger.info('任务已取消: ${inProgressTask.fileName}');
      notifyListeners();
      _processQueue();
    } else if (pendingTask != null) {
      _pendingQueue.remove(pendingTask);
      logger.info('任务已移除: ${pendingTask.fileName}');
      notifyListeners();
    }
  }

  /// 删除已完成的任务
  void removeCompletedTask(String taskId) {
    _completedQueue.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  /// 删除失败的任务
  void removeFailedTask(String taskId) {
    _failedQueue.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  /// 清空已完成的任务
  void clearCompleted() {
    _completedQueue.clear();
    notifyListeners();
  }

  /// 清空失败的任务
  void clearFailed() {
    _failedQueue.clear();
    notifyListeners();
  }

  /// 清空所有任务
  void clearAll() {
    _pendingQueue.clear();
    _inProgressQueue.clear();
    _completedQueue.clear();
    _failedQueue.clear();
    for (var sub in _activeSubscriptions) {
      sub.cancel();
    }
    _activeSubscriptions.clear();
    notifyListeners();
  }

  /// 根据ID查找任务
  TransferTask? _findTask(String taskId) {
    return _findTaskInProgress(taskId) ??
           _findTaskInPending(taskId) ??
           _completedQueue.firstWhere((t) => t.id == taskId, orElse: () => _failedQueue.firstWhere((t) => t.id == taskId, orElse: () => throw Exception('Task not found: $taskId')));
  }

  TransferTask? _findTaskInProgress(String taskId) {
    try {
      return _inProgressQueue.firstWhere((t) => t.id == taskId);
    } catch (e) {
      return null;
    }
  }

  TransferTask? _findTaskInPending(String taskId) {
    try {
      return _pendingQueue.firstWhere((t) => t.id == taskId);
    } catch (e) {
      return null;
    }
  }

  void _moveToCompleted(TransferTask task) {
    _inProgressQueue.remove(task);
    _completedQueue.insert(0, task);
  }

  /// 获取进行中的任务数量
  int get inProgressCount => _inProgressQueue.length;

  /// 获取待处理的任务数量
  int get pendingCount => _pendingQueue.length;

  /// 获取已完成的任务数量
  int get completedCount => _completedQueue.length;

  /// 获取失败的任务数量
  int get failedCount => _failedQueue.length;

  @override
  void dispose() {
    _taskUpdateController.close();
    for (var sub in _activeSubscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}
