import 'platform_type.dart';

class PlatformCredential {
  final PlatformType platformType;
  final String secretId;
  final String secretKey;
  final String region;

  PlatformCredential({
    required this.platformType,
    required this.secretId,
    required this.secretKey,
    this.region = 'ap-beijing',
  });

  Map<String, dynamic> toJson() {
    return {
      'platformType': platformType.value,
      'secretId': secretId,
      'secretKey': secretKey,
      'region': region,
    };
  }

  factory PlatformCredential.fromJson(Map<String, dynamic> json) {
    return PlatformCredential(
      platformType: PlatformTypeExtension.fromValue(json['platformType']),
      secretId: json['secretId'],
      secretKey: json['secretKey'],
      region: json['region'] ?? 'ap-beijing',
    );
  }
}
