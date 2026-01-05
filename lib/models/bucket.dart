class Bucket {
  final String name;
  final String region;
  final DateTime? creationDate;
  final bool webdavEnabled;
  final int? webdavPort;

  Bucket({
    required this.name,
    required this.region,
    this.creationDate,
    this.webdavEnabled = false,
    this.webdavPort,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'region': region,
      'creationDate': creationDate?.toIso8601String(),
      'webdavEnabled': webdavEnabled,
      'webdavPort': webdavPort,
    };
  }

  factory Bucket.fromJson(Map<String, dynamic> json) {
    return Bucket(
      name: json['name'],
      region: json['region'],
      creationDate: json['creationDate'] != null
          ? DateTime.parse(json['creationDate'])
          : null,
      webdavEnabled: json['webdavEnabled'] ?? false,
      webdavPort: json['webdavPort'],
    );
  }

  Bucket copyWith({
    String? name,
    String? region,
    DateTime? creationDate,
    bool? webdavEnabled,
    int? webdavPort,
  }) {
    return Bucket(
      name: name ?? this.name,
      region: region ?? this.region,
      creationDate: creationDate ?? this.creationDate,
      webdavEnabled: webdavEnabled ?? this.webdavEnabled,
      webdavPort: webdavPort ?? this.webdavPort,
    );
  }
}
