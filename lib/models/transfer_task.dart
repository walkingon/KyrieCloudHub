enum TransferType {
  upload,
  download,
}

enum TransferStatus {
  pending,
  inProgress,
  paused,
  completed,
  failed,
  cancelled,
}

class TransferTask {
  final String id;
  final String fileName;
  final String filePath;
  final String bucketName;
  final String objectKey;
  final TransferType type;
  final int totalSize;
  
  TransferStatus status;
  int transferredSize;
  String? errorMessage;
  DateTime? startTime;
  DateTime? endTime;

  TransferTask({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.bucketName,
    required this.objectKey,
    required this.type,
    required this.totalSize,
    this.status = TransferStatus.pending,
    this.transferredSize = 0,
    this.errorMessage,
    this.startTime,
    this.endTime,
  });

  double get progress {
    if (totalSize == 0) return 0.0;
    return transferredSize / totalSize;
  }

  bool get isCompleted => status == TransferStatus.completed;
  bool get isInProgress => status == TransferStatus.inProgress;
  bool get isPaused => status == TransferStatus.paused;
  bool get isFailed => status == TransferStatus.failed;
  bool get isCancelled => status == TransferStatus.cancelled;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'filePath': filePath,
      'bucketName': bucketName,
      'objectKey': objectKey,
      'type': type.name,
      'totalSize': totalSize,
      'status': status.name,
      'transferredSize': transferredSize,
      'errorMessage': errorMessage,
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
    };
  }

  factory TransferTask.fromJson(Map<String, dynamic> json) {
    return TransferTask(
      id: json['id'],
      fileName: json['fileName'],
      filePath: json['filePath'],
      bucketName: json['bucketName'],
      objectKey: json['objectKey'],
      type: json['type'] == 'upload' ? TransferType.upload : TransferType.download,
      totalSize: json['totalSize'],
      status: TransferStatus.values.firstWhere((e) => e.name == json['status']),
      transferredSize: json['transferredSize'] ?? 0,
      errorMessage: json['errorMessage'],
      startTime: json['startTime'] != null 
          ? DateTime.parse(json['startTime']) 
          : null,
      endTime: json['endTime'] != null 
          ? DateTime.parse(json['endTime']) 
          : null,
    );
  }
}
