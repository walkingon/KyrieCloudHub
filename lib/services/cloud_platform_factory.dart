import '../models/platform_type.dart';
import '../models/platform_credential.dart';
import 'api/cloud_platform_api.dart';

class CloudPlatformFactory {
  static ICloudPlatformApi createApi(
    PlatformType platformType,
    PlatformCredential credential,
  ) {
    switch (platformType) {
      case PlatformType.tencentCloud:
        throw UnimplementedError('Tencent Cloud API not implemented yet');
      case PlatformType.aliCloud:
        throw UnimplementedError('Ali Cloud API not implemented yet');
    }
  }
}
