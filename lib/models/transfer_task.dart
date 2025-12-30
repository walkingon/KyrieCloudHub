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

/// 分片信息
class PartInfo {
  final int partNumber;
  final int offset;
  final int size;
  String? etag;
  bool uploaded;

  PartInfo({
    required this.partNumber,
    required this.offset,
    required this.size,
    this.etag,
    this.uploaded = false,
  });

  /// 更新ETag
  void updateEtag(String newEtag) {
    etag = newEtag;
  }

  /// 标记为已上传
  void markUploaded(String newEtag) {
    uploaded = true;
    etag = newEtag;
  }

  Map<String, dynamic> toJson() {
    return {
      'partNumber': partNumber,
      'offset': offset,
      'size': size,
      'etag': etag,
      'uploaded': uploaded,
    };
  }

  factory PartInfo.fromJson(Map<String, dynamic> json) {
    return PartInfo(
      partNumber: json['partNumber'],
      offset: json['offset'],
      size: json['size'],
      etag: json['etag'],
      uploaded: json['uploaded'] ?? false,
    );
  }
}

/// 断点续传信息
class ResumeInfo {
  final String? uploadId;
  final List<PartInfo> uploadedParts;
  final int partSize;
  final String region;

  ResumeInfo({
    this.uploadId,
    required this.uploadedParts,
    required this.partSize,
    required this.region,
  });

  Map<String, dynamic> toJson() {
    return {
      'uploadId': uploadId,
      'uploadedParts': uploadedParts.map((e) => e.toJson()).toList(),
      'partSize': partSize,
      'region': region,
    };
  }

  factory ResumeInfo.fromJson(Map<String, dynamic> json) {
    return ResumeInfo(
      uploadId: json['uploadId'],
      uploadedParts: (json['uploadedParts'] as List<dynamic>)
          .map((e) => PartInfo.fromJson(e))
          .toList(),
      partSize: json['partSize'],
      region: json['region'],
    );
  }
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

  // 分片上传相关字段
  final String? localFilePath;
  final String region;
  final int? partSize; // 分片大小（字节），默认1MB
  final String? uploadId; // 分片上传ID
  final List<PartInfo> parts; // 已上传的分片信息
  final ResumeInfo? resumeInfo; // 断点续传信息

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
    this.localFilePath,
    required this.region,
    this.partSize,
    this.uploadId,
    this.parts = const [],
    this.resumeInfo,
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

  /// 是否支持断点续传
  bool get supportsResume => type == TransferType.upload && totalSize > 1024 * 1024;

  /// 获取下一个需要上传的分片号
  int get nextPartNumber {
    if (parts.isEmpty) return 1;
    return parts.map((p) => p.partNumber).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// 获取已上传的分片数
  int get uploadedPartCount => parts.where((p) => p.uploaded).length;

  /// 更新uploadId
  void setUploadId(String newUploadId) {
    // 创建一个新的TransferTask是不行的，我们需要使用一个可变字段
    // 由于final字段不能直接赋值，我们使用resumeInfo来存储
  }

  /// 添加或更新分片信息
  void updatePart(PartInfo part) {
    final index = parts.indexWhere((p) => p.partNumber == part.partNumber);
    if (index >= 0) {
      parts[index] = part;
    } else {
      parts.add(part);
    }
  }

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
      'localFilePath': localFilePath,
      'region': region,
      'partSize': partSize,
      'uploadId': uploadId,
      'parts': parts.map((e) => e.toJson()).toList(),
      'resumeInfo': resumeInfo?.toJson(),
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
      localFilePath: json['localFilePath'],
      region: json['region'],
      partSize: json['partSize'],
      uploadId: json['uploadId'],
      parts: (json['parts'] as List<dynamic>?)
              ?.map((e) => PartInfo.fromJson(e))
              .toList() ??
          [],
      resumeInfo: json['resumeInfo'] != null
          ? ResumeInfo.fromJson(json['resumeInfo'])
          : null,
    );
  }

  /// 创建上传任务
  static TransferTask createUpload({
    required String id,
    required String fileName,
    required String filePath,
    required String bucketName,
    required String objectKey,
    required int totalSize,
    required String region,
    int partSize = 1024 * 1024, // 默认1MB分片
  }) {
    return TransferTask(
      id: id,
      fileName: fileName,
      filePath: filePath,
      bucketName: bucketName,
      objectKey: objectKey,
      type: TransferType.upload,
      totalSize: totalSize,
      region: region,
      localFilePath: filePath,
      partSize: partSize,
    );
  }

  /// 创建下载任务
  static TransferTask createDownload({
    required String id,
    required String fileName,
    required String filePath,
    required String bucketName,
    required String objectKey,
    required int totalSize,
    required String region,
  }) {
    return TransferTask(
      id: id,
      fileName: fileName,
      filePath: filePath,
      bucketName: bucketName,
      objectKey: objectKey,
      type: TransferType.download,
      totalSize: totalSize,
      region: region,
      localFilePath: filePath,
    );
  }
}
