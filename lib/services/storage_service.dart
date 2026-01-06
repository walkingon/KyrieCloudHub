import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/platform_type.dart';
import '../models/platform_credential.dart';

class StorageService {
  static const String _keyLastPlatform = 'last_platform';
  static const String _keyCredentialPrefix = 'credential_';
  static const String _keyDownloadDirectory = 'download_directory';

  Future<void> saveLastPlatform(PlatformType platformType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastPlatform, platformType.value);
  }

  Future<PlatformType?> getLastPlatform() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyLastPlatform);
    if (value == null) return null;
    try {
      return PlatformTypeExtension.fromValue(value);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearLastPlatform() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastPlatform);
  }

  Future<void> saveCredential(PlatformCredential credential) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyCredentialPrefix + credential.platformType.value;
    final jsonString = jsonEncode(credential.toJson());
    await prefs.setString(key, jsonString);
  }

  Future<PlatformCredential?> getCredential(PlatformType platformType) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyCredentialPrefix + platformType.value;
    final jsonString = prefs.getString(key);
    if (jsonString == null) return null;
    try {
      final json = jsonDecode(jsonString);
      return PlatformCredential.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearCredential(PlatformType platformType) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyCredentialPrefix + platformType.value;
    await prefs.remove(key);
  }

  Future<bool> hasCredential(PlatformType platformType) async {
    final credential = await getCredential(platformType);
    return credential != null;
  }

  // ==================== 下载目录设置 ====================

  Future<void> saveDownloadDirectory(String directoryPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDownloadDirectory, directoryPath);
  }

  Future<String?> getDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDownloadDirectory);
  }

  Future<void> clearDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDownloadDirectory);
  }
}
