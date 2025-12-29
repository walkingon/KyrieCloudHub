import '../models/platform_type.dart';
import '../models/platform_credential.dart';
import 'api/cloud_platform_api.dart';
import 'api/tencent_cos_api.dart';
import 'api/http_client.dart';

class CloudPlatformFactory {
  final HttpClient httpClient;

  CloudPlatformFactory(this.httpClient);

  ICloudPlatformApi? createApi(
    PlatformType platformType, {
    PlatformCredential? credential,
  }) {
    switch (platformType) {
      case PlatformType.tencentCloud:
        if (credential != null) {
          return TencentCosApi(credential, httpClient);
        }
        return null;
      case PlatformType.aliCloud:
        throw UnimplementedError('Ali Cloud API not implemented yet');
    }
  }
}
