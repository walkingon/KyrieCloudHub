import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/transfer_task.dart';
import '../services/api/cloud_platform_api.dart';
import '../services/storage_service.dart';
import '../utils/file_chunk_reader.dart';

/// 传输任务事件类型
enum TransferEventType {
  taskAdded,
  taskProgress,
  taskCompleted,
  taskFailed,
  taskPaused,
  taskResumed,
  taskCancelled,
}

/// 传输任务事件
class TransferTaskEvent {
  final TransferTask task;
  final TransferEventType type;
  final String? message;

  TransferTaskEvent({
    required this.task,
    required this.type,
    this.message,
  });
}

/// 传输任务队列服务
/// 管理所有传输任务的生命周期，支持暂停、恢复、取消和断点续传
class TransferQueueService extends ChangeNotifier {
  static final TransferQueueService _instance = TransferQueueService._internal();
  factory TransferQueueService() => _instance;
  TransferQueueService._internal();

  final StorageService _storageService = StorageService();
  final Map<String, TransferTask> _tasks = {};
  final Map<String, StreamSubscription<TransferTaskEvent>> _eventSubscriptions = {};
  final Map<String, Completer<void>> _taskCompleters = {};
  final Set<String> _pausedTasks = {};

  // 并发控制
  int _maxConcurrentTasks = 2;
  int _runningTasks = 0;
  final List<String> _pendingTaskIds = [];

  // 当前活动的API实例
  ICloudPlatformApi? _currentApi;

  // 事件流
  final StreamController<TransferTaskEvent> _eventController =
      StreamController<TransferTaskEvent>.broadcast();
  Stream<TransferTaskEvent> get eventStream => _eventController.stream;

  // 任务列表（用于UI展示）
  List<TransferTask> get allTasks => List.unmodifiable(_tasks.values.toList());

  /// 进行中的任务
  List<TransferTask> get inProgressTasks =>
      _tasks.values.where((t) => t.isInProgress).toList();

  /// 已完成的任务
  List<TransferTask> get completedTasks =>
      _tasks.values.where((t) => t.isCompleted).toList();

  /// 待处理的任务
  List<TransferTask> get pendingTasks =>
      _tasks.values.where((t) => t.status == TransferStatus.pending).toList();

  /// 设置最大并发任务数
  void setMaxConcurrent(int max) {
    _maxConcurrentTasks = max;
    _processNext();
  }

  /// 设置当前API实例（由外部传入）
  void setApi(ICloudPlatformApi api) {
    _currentApi = api;
  }

  /// 添加上传任务
  Future<void> addUploadTask({
    required String filePath,
    required String bucketName,
    required String objectKey,
    required int fileSize,
    required String region,
  }) async {
    final taskId = _generateTaskId();
    final fileName = filePath.split(Platform.pathSeparator).last;

    final task = TransferTask.createUpload(
      id: taskId,
      fileName: fileName,
      filePath: filePath,
      bucketName: bucketName,
      objectKey: objectKey,
      totalSize: fileSize,
      region: region,
    );

    await _addTask(task);
  }

  /// 添加下载任务
  Future<void> addDownloadTask({
    required String fileName,
    required String savePath,
    required String bucketName,
    required String objectKey,
    required int fileSize,
    required String region,
  }) async {
    final taskId = _generateTaskId();

    final task = TransferTask.createDownload(
      id: taskId,
      fileName: fileName,
      filePath: savePath,
      bucketName: bucketName,
      objectKey: objectKey,
      totalSize: fileSize,
      region: region,
    );

    await _addTask(task);
  }

  Future<void> _addTask(TransferTask task) async {
    _tasks[task.id] = task;
    _pendingTaskIds.add(task.id);

    // 尝试恢复之前的进度
    final savedTask = await _storageService.getTransferTaskFull(task.id);
    if (savedTask != null) {
      _tasks[task.id] = savedTask;
      if (savedTask.status == TransferStatus.paused) {
        _pausedTasks.add(savedTask.id);
      }
    }

    // 保存任务信息
    await _storageService.saveTransferTaskFull(task);

    // 发送任务添加事件
    _emitEvent(TransferTaskEvent(task: task, type: TransferEventType.taskAdded));

    // 触发任务处理
    _processNext();

    notifyListeners();
  }

  /// 暂停任务
  Future<void> pauseTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || !task.isInProgress) return;

    // 标记任务为暂停
    _pausedTasks.add(taskId);
    task.status = TransferStatus.paused;
    await _storageService.saveTransferTaskFull(task);

    // 取消正在进行的任务
    _cancelTaskExecution(taskId);

    _emitEvent(TransferTaskEvent(
      task: task,
      type: TransferEventType.taskPaused,
      message: '任务已暂停',
    ));

    notifyListeners();
  }

  /// 恢复任务
  Future<void> resumeTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status != TransferStatus.paused) return;

    // 移除暂停标记
    _pausedTasks.remove(taskId);
    task.status = TransferStatus.pending;
    await _storageService.saveTransferTaskFull(task);

    // 重新加入待处理队列
    if (!_pendingTaskIds.contains(taskId)) {
      _pendingTaskIds.add(taskId);
    }

    _emitEvent(TransferTaskEvent(
      task: task,
      type: TransferEventType.taskResumed,
      message: '任务已恢复',
    ));

    _processNext();
    notifyListeners();
  }

  /// 取消任务
  Future<void> cancelTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    // 取消正在进行的任务
    _cancelTaskExecution(taskId);

    // 标记为已取消
    task.status = TransferStatus.cancelled;
    task.endTime = DateTime.now();
    await _storageService.saveTransferTaskFull(task);

    // 清理断点续传信息
    await _storageService.clearResumeInfo(taskId);

    // 从队列中移除
    _pendingTaskIds.remove(taskId);

    _emitEvent(TransferTaskEvent(
      task: task,
      type: TransferEventType.taskCancelled,
      message: '任务已取消',
    ));

    notifyListeners();
  }

  /// 删除已完成的任务
  Future<void> removeTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || (!task.isCompleted && !task.isCancelled)) return;

    _tasks.remove(taskId);
    await _storageService.clearTransferTask(taskId);
    await _storageService.clearResumeInfo(taskId);

    notifyListeners();
  }

  /// 重试失败的任务
  Future<void> retryTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || !task.isFailed) return;

    // 重置任务状态
    task.status = TransferStatus.pending;
    task.transferredSize = 0;
    task.errorMessage = null;
    task.startTime = null;
    task.endTime = null;
    await _storageService.saveTransferTaskFull(task);

    if (!_pendingTaskIds.contains(taskId)) {
      _pendingTaskIds.add(taskId);
    }

    _processNext();
    notifyListeners();
  }

  void _cancelTaskExecution(String taskId) {
    // 取消completer
    final completer = _taskCompleters[taskId];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _taskCompleters.remove(taskId);

    // 取消订阅
    final subscription = _eventSubscriptions[taskId];
    subscription?.cancel();
    _eventSubscriptions.remove(taskId);
  }

  /// 处理下一个待处理任务
  void _processNext() {
    while (_runningTasks < _maxConcurrentTasks && _pendingTaskIds.isNotEmpty) {
      final taskId = _pendingTaskIds.removeAt(0);
      final task = _tasks[taskId];

      if (task == null || task.isCompleted || task.isCancelled) continue;
      if (_pausedTasks.contains(taskId)) continue;

      _executeTask(task);
    }
  }

  void _executeTask(TransferTask task) async {
    _runningTasks++;
    task.status = TransferStatus.inProgress;
    task.startTime ??= DateTime.now();

    await _storageService.saveTransferTaskFull(task);
    notifyListeners();

    final completer = Completer<void>();
    _taskCompleters[task.id] = completer;

    try {
      if (task.type == TransferType.upload) {
        await _executeUpload(task, completer);
      } else {
        await _executeDownload(task, completer);
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    _runningTasks--;
    _taskCompleters.remove(task.id);
    _eventSubscriptions.remove(task.id);

    // 继续处理下一个任务
    _processNext();
  }

  Future<void> _executeUpload(TransferTask task, Completer<void> completer) async {
    final api = _currentApi;
    if (api == null) {
      _failTask(task, 'API未初始化');
      return;
    }

    final file = File(task.localFilePath ?? task.filePath);

    if (!await file.exists()) {
      _failTask(task, '文件不存在: ${task.filePath}');
      return;
    }

    try {
      // 检查是否支持断点续传
      final shouldUseMultipart = task.totalSize > 1024 * 1024; // 大于1MB使用分片上传

      if (shouldUseMultipart) {
        await _multipartUpload(task, file, completer, api);
      } else {
        await _simpleUpload(task, file, completer, api);
      }
    } catch (e) {
      _failTask(task, e.toString());
    }
  }

  Future<void> _simpleUpload(TransferTask task, File file, Completer<void> completer, ICloudPlatformApi api) async {
    final fileBytes = await file.readAsBytes();

    task.status = TransferStatus.inProgress;
    await _storageService.saveTransferTaskFull(task);

    final response = await api.uploadObject(
      bucketName: task.bucketName,
      region: task.region,
      objectKey: task.objectKey,
      data: fileBytes,
      onProgress: (sent, total) {
        if (completer.isCompleted) return;
        _updateTaskProgress(task, sent);
      },
    );

    if (response.success) {
      _completeTask(task);
    } else {
      _failTask(task, response.errorMessage ?? '上传失败');
    }
  }

  Future<void> _multipartUpload(
    TransferTask task,
    File file,
    Completer<void> completer,
    ICloudPlatformApi api,
  ) async {
    final chunkReader = FileChunkReader(file, chunkSize: task.partSize ?? 1024 * 1024);

    // 获取或初始化uploadId
    String? uploadId = task.uploadId;
    List<PartInfo> parts = List<PartInfo>.from(task.parts);

    // 如果没有uploadId，初始化分片上传
    if (uploadId == null || uploadId.isEmpty) {
      final initResult = await api.initMultipartUpload(
        bucketName: task.bucketName,
        region: task.region,
        objectKey: task.objectKey,
      );

      if (!initResult.success) {
        _failTask(task, initResult.errorMessage ?? '初始化分片上传失败');
        await chunkReader.close();
        return;
      }

      uploadId = initResult.data!;
      // 更新任务的uploadId需要创建新实例
      task = _tasks[task.id]!.copyWith(uploadId: uploadId);
      _tasks[task.id] = task;
    }

    // 保存uploadId
    await _storageService.saveResumeInfo(task.id, ResumeInfo(
      uploadId: uploadId,
      uploadedParts: parts,
      partSize: task.partSize ?? 1024 * 1024,
      region: task.region,
    ));

    // 继续上传未完成的分片
    while (chunkReader.hasMore) {
      if (completer.isCompleted) {
        await chunkReader.close();
        return;
      }

      // 检查是否已暂停
      if (_pausedTasks.contains(task.id)) {
        await chunkReader.close();
        return;
      }

      final (data: chunkData, partInfo: partInfo) = await chunkReader.readNextChunk();

      // 检查该分片是否已上传
      final existingPart = parts.firstWhere(
        (p) => p.partNumber == partInfo.partNumber,
        orElse: () => partInfo,
      );

      if (existingPart.uploaded && existingPart.etag != null) {
        // 分片已上传，跳过
        _updateTaskProgress(task, existingPart.offset + existingPart.size);
        continue;
      }

      // 上传分片
      final uploadResult = await api.uploadPart(
        bucketName: task.bucketName,
        region: task.region,
        objectKey: task.objectKey,
        uploadId: uploadId,
        partNumber: partInfo.partNumber,
        data: chunkData,
        onProgress: (sent, total) {
          if (completer.isCompleted) return;
          _updateTaskProgress(task, existingPart.offset + sent.toInt());
        },
      );

      if (!uploadResult.success) {
        _failTask(task, uploadResult.errorMessage ?? '分片上传失败');
        await chunkReader.close();
        return;
      }

      // 更新分片信息
      partInfo.markUploaded(uploadResult.data!);

      // 更新任务的分片列表
      final partIndex = parts.indexWhere((p) => p.partNumber == partInfo.partNumber);
      if (partIndex >= 0) {
        parts[partIndex] = partInfo;
      } else {
        parts.add(partInfo);
      }

      // 创建更新后的任务
      final updatedTask = task.copyWith(
        parts: parts,
        transferredSize: partInfo.offset + partInfo.size,
      );
      _tasks[task.id] = updatedTask;

      // 保存进度
      await _storageService.saveTransferTaskFull(updatedTask);
      await _storageService.saveResumeInfo(task.id, ResumeInfo(
        uploadId: uploadId,
        uploadedParts: parts,
        partSize: task.partSize ?? 1024 * 1024,
        region: task.region,
      ));

      _emitProgress(updatedTask);
    }

    await chunkReader.close();

    // 完成分片上传
    final completeResult = await api.completeMultipartUpload(
      bucketName: task.bucketName,
      region: task.region,
      objectKey: task.objectKey,
      uploadId: uploadId,
      parts: parts.where((p) => p.uploaded).toList(),
    );

    if (completeResult.success) {
      _completeTask(task);
    } else {
      _failTask(task, completeResult.errorMessage ?? '完成分片上传失败');
    }

    // 清理断点续传信息
    await _storageService.clearResumeInfo(task.id);
  }

  Future<void> _executeDownload(TransferTask task, Completer<void> completer) async {
    final api = _currentApi;
    if (api == null) {
      _failTask(task, 'API未初始化');
      return;
    }

    try {
      final response = await api.downloadObject(
        bucketName: task.bucketName,
        region: task.region,
        objectKey: task.objectKey,
        onProgress: (received, total) {
          if (completer.isCompleted) return;
          _updateTaskProgress(task, received);
        },
      );

      if (!response.success) {
        _failTask(task, response.errorMessage ?? '下载失败');
        return;
      }

      // 保存文件
      final file = File(task.filePath);
      await file.writeAsBytes(response.data!);
      _updateTaskProgress(task, task.totalSize);

      _completeTask(task);
    } catch (e) {
      _failTask(task, e.toString());
    }
  }

  void _updateTaskProgress(TransferTask task, int transferredSize) {
    task.transferredSize = transferredSize;
    _storageService.saveTransferTaskFull(task);
    _emitEvent(TransferTaskEvent(
      task: task,
      type: TransferEventType.taskProgress,
    ));
    notifyListeners();
  }

  void _emitProgress(TransferTask task) {
    _emitEvent(TransferTaskEvent(
      task: task,
      type: TransferEventType.taskProgress,
    ));
    notifyListeners();
  }

  void _completeTask(TransferTask task) {
    task.status = TransferStatus.completed;
    task.endTime = DateTime.now();
    task.transferredSize = task.totalSize;

    _storageService.saveTransferTaskFull(task);

    _emitEvent(TransferTaskEvent(
      task: task,
      type: TransferEventType.taskCompleted,
      message: '传输完成',
    ));

    notifyListeners();
  }

  void _failTask(TransferTask task, String error) {
    task.status = TransferStatus.failed;
    task.endTime = DateTime.now();
    task.errorMessage = error;

    _storageService.saveTransferTaskFull(task);

    _emitEvent(TransferTaskEvent(
      task: task,
      type: TransferEventType.taskFailed,
      message: error,
    ));

    notifyListeners();
  }

  void _emitEvent(TransferTaskEvent event) {
    _eventController.add(event);
  }

  String _generateTaskId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch % 1000}';
  }

  /// 从存储恢复未完成的任务
  Future<void> restoreTasks() async {
    final pendingIds = await _storageService.getPendingTransferTaskIds();

    for (final taskId in pendingIds) {
      final task = await _storageService.getTransferTaskFull(taskId);
      if (task != null) {
        _tasks[task.id] = task;
        if (task.status == TransferStatus.paused) {
          _pausedTasks.add(task.id);
        } else if (task.status == TransferStatus.pending ||
            task.status == TransferStatus.inProgress) {
          // 重新加入队列
          _pendingTaskIds.add(task.id);
        }
      }
    }

    notifyListeners();
  }

  /// 清理已完成的旧任务
  Future<void> cleanupOldTasks({int keepCount = 20}) async {
    final completedTasks = _tasks.values
        .where((t) => t.isCompleted)
        .toList()
      ..sort((a, b) => b.endTime?.compareTo(a.endTime ?? DateTime.now()) ?? 0);

    while (completedTasks.length > keepCount) {
      final oldTask = completedTasks.removeLast();
      await removeTask(oldTask.id);
    }
  }

  @override
  void dispose() {
    _eventController.close();
    for (final subscription in _eventSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }
}

/// 扩展TransferTask添加copyWith方法
extension TransferTaskCopyWith on TransferTask {
  TransferTask copyWith({
    String? id,
    String? fileName,
    String? filePath,
    String? bucketName,
    String? objectKey,
    TransferType? type,
    int? totalSize,
    TransferStatus? status,
    int? transferredSize,
    String? errorMessage,
    DateTime? startTime,
    DateTime? endTime,
    String? localFilePath,
    String? region,
    int? partSize,
    String? uploadId,
    List<PartInfo>? parts,
    ResumeInfo? resumeInfo,
  }) {
    return TransferTask(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      bucketName: bucketName ?? this.bucketName,
      objectKey: objectKey ?? this.objectKey,
      type: type ?? this.type,
      totalSize: totalSize ?? this.totalSize,
      status: status ?? this.status,
      transferredSize: transferredSize ?? this.transferredSize,
      errorMessage: errorMessage ?? this.errorMessage,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      localFilePath: localFilePath ?? this.localFilePath,
      region: region ?? this.region,
      partSize: partSize ?? this.partSize,
      uploadId: uploadId ?? this.uploadId,
      parts: parts ?? this.parts,
      resumeInfo: resumeInfo ?? this.resumeInfo,
    );
  }
}
