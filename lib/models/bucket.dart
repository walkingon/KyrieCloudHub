import 'storage_class.dart';

class Bucket {
  final String name;
  final String region;
  final DateTime? creationDate;
  final StorageClass? storageClass;

  Bucket({
    required this.name,
    required this.region,
    this.creationDate,
    this.storageClass,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'region': region,
      'creationDate': creationDate?.toIso8601String(),
      'storageClass': storageClass?.name,
    };
  }

  factory Bucket.fromJson(Map<String, dynamic> json) {
    return Bucket(
      name: json['name'],
      region: json['region'],
      creationDate: json['creationDate'] != null
          ? DateTime.parse(json['creationDate'])
          : null,
      storageClass: json['storageClass'] != null
          ? StorageClass.values.firstWhere(
              (e) => e.name == json['storageClass'],
              orElse: () => StorageClass.standard,
            )
          : null,
    );
  }

  Bucket copyWith({
    String? name,
    String? region,
    DateTime? creationDate,
    StorageClass? storageClass,
  }) {
    return Bucket(
      name: name ?? this.name,
      region: region ?? this.region,
      creationDate: creationDate ?? this.creationDate,
      storageClass: storageClass ?? this.storageClass,
    );
  }
}
