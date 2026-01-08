/// 存储类型枚举
///
/// 支持腾讯云 COS 和阿里云 OSS 的存储类型
enum StorageClass {
  /// 标准存储（默认）
  standard('标准存储'),

  /// 低频存储
  /// - 腾讯云: STANDARD_IA
  /// - 阿里云: IA
  standardIa('低频存储'),

  /// 归档存储
  /// - 腾讯云: ARCHIVE
  /// - 阿里云: Archive
  archive('归档存储'),

  /// 深度归档存储（仅腾讯云）
  /// - 腾讯云: DEEP_ARCHIVE
  deepArchive('深度归档存储'),

  /// 智能分层存储（仅腾讯云）
  /// - 腾讯云: INTELLIGENT_TIERING
  intelligentTiering('智能分层存储'),

  /// 冷归档存储（仅阿里云）
  /// - 阿里云: ColdArchive
  coldArchive('冷归档存储'),

  /// 深度冷归档存储（仅阿里云）
  /// - 阿里云: DeepColdArchive
  deepColdArchive('深度冷归档存储');

  final String displayName;

  const StorageClass(this.displayName);

  /// 默认存储类型
  static StorageClass get defaultValue => standard;

  /// 获取腾讯云 COS 存储类型值
  String get tencentValue {
    switch (this) {
      case StorageClass.standard:
        return 'STANDARD';
      case StorageClass.standardIa:
        return 'STANDARD_IA';
      case StorageClass.archive:
        return 'ARCHIVE';
      case StorageClass.deepArchive:
        return 'DEEP_ARCHIVE';
      case StorageClass.intelligentTiering:
        return 'INTELLIGENT_TIERING';
      case StorageClass.coldArchive:
      case StorageClass.deepColdArchive:
        return 'ARCHIVE';
    }
  }

  /// 获取阿里云 OSS 存储类型值
  String get aliyunValue {
    switch (this) {
      case StorageClass.standard:
        return 'Standard';
      case StorageClass.standardIa:
        return 'IA';
      case StorageClass.archive:
        return 'Archive';
      case StorageClass.deepArchive:
        return 'Archive';
      case StorageClass.intelligentTiering:
        return 'Standard';
      case StorageClass.coldArchive:
        return 'ColdArchive';
      case StorageClass.deepColdArchive:
        return 'DeepColdArchive';
    }
  }

  /// 获取存储类型 Header 值
  ///
  /// [platform] 云平台类型
  String getHeaderValue(String platform) {
    if (platform == 'tencent') {
      return tencentValue;
    } else if (platform == 'aliyun') {
      return aliyunValue;
    }
    return 'STANDARD';
  }

  /// 从腾讯云 API 返回值解析存储类型
  static StorageClass fromTencentValue(String value) {
    switch (value.toUpperCase()) {
      case 'STANDARD_IA':
        return StorageClass.standardIa;
      case 'ARCHIVE':
        return StorageClass.archive;
      case 'DEEP_ARCHIVE':
        return StorageClass.deepArchive;
      case 'INTELLIGENT_TIERING':
        return StorageClass.intelligentTiering;
      case 'STANDARD':
      default:
        return StorageClass.standard;
    }
  }

  /// 从阿里云 API 返回值解析存储类型
  static StorageClass fromAliyunValue(String value) {
    switch (value) {
      case 'IA':
        return StorageClass.standardIa;
      case 'Archive':
        return StorageClass.archive;
      case 'ColdArchive':
        return StorageClass.coldArchive;
      case 'DeepColdArchive':
        return StorageClass.deepColdArchive;
      case 'Standard':
      default:
        return StorageClass.standard;
    }
  }
}
