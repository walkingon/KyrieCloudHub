import '../models/platform_type.dart';
import '../models/platform_credential.dart';
import 'api/cloud_platform_api.dart';
import 'api/tencent_cos_api.dart';
import 'api/ali_yun_oss_api.dart';

class CloudPlatformFactory {
  CloudPlatformFactory();

  ICloudPlatformApi? createApi(
    PlatformType platformType, {
    PlatformCredential? credential,
  }) {
    switch (platformType) {
      case PlatformType.tencentCloud:
        if (credential != null) {
          return TencentCosApi(credential);
        }
        return null;
      case PlatformType.aliCloud:
        if (credential != null) {
          return AliyunOssApi(credential);
        }
        return null;
    }
  }
}
