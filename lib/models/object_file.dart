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

  ObjectFile({
    required this.key,
    required this.name,
    required this.type,
    required this.size,
    this.lastModified,
    this.etag,
  });

  String get extension {
    if (type == ObjectType.folder) return '';
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  bool get isFolder => type == ObjectType.folder;

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'type': type.name,
      'size': size,
      'lastModified': lastModified?.toIso8601String(),
      'etag': etag,
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
    );
  }
}
