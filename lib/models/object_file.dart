import 'storage_class.dart';

enum ObjectType {
  file,
  folder,
}

class ObjectFile {
  final String key;
  final String name;
  final ObjectType type;
  final int size;
  final DateTime? lastModified;
  final String? etag;
  final StorageClass? storageClass;

  ObjectFile({
    required this.key,
    required this.name,
    required this.type,
    required this.size,
    this.lastModified,
    this.etag,
    this.storageClass,
  });

  String get extension {
    if (type == ObjectType.folder) return '';
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  bool get isFolder => type == ObjectType.folder;

  /// 是否显示存储类型（非标准存储才显示）
  bool get shouldShowStorageClass =>
      storageClass != null && storageClass != StorageClass.standard;

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'type': type.name,
      'size': size,
      'lastModified': lastModified?.toIso8601String(),
      'etag': etag,
      'storageClass': storageClass?.name,
    };
  }

  factory ObjectFile.fromJson(Map<String, dynamic> json) {
    return ObjectFile(
      key: json['key'],
      name: json['name'],
      type: json['type'] == 'folder' ? ObjectType.folder : ObjectType.file,
      size: json['size'],
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'])
          : null,
      etag: json['etag'],
      storageClass: json['storageClass'] != null
          ? StorageClass.values.firstWhere(
              (e) => e.name == json['storageClass'],
              orElse: () => StorageClass.standard,
            )
          : null,
    );
  }
}
