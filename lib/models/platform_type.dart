enum PlatformType {
  tencentCloud,
  aliCloud,
}

extension PlatformTypeExtension on PlatformType {
  String get displayName {
    switch (this) {
      case PlatformType.tencentCloud:
        return '腾讯云';
      case PlatformType.aliCloud:
        return '阿里云';
    }
  }

  String get value {
    switch (this) {
      case PlatformType.tencentCloud:
        return 'tencent_cloud';
      case PlatformType.aliCloud:
        return 'ali_cloud';
    }
  }

  static PlatformType fromValue(String value) {
    switch (value) {
      case 'tencent_cloud':
        return PlatformType.tencentCloud;
      case 'ali_cloud':
        return PlatformType.aliCloud;
      default:
        throw ArgumentError('Unknown platform type: $value');
    }
  }
}
