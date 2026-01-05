class Bucket {
  final String name;
  final String region;
  final DateTime? creationDate;

  Bucket({
    required this.name,
    required this.region,
    this.creationDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'region': region,
      'creationDate': creationDate?.toIso8601String(),
    };
  }

  factory Bucket.fromJson(Map<String, dynamic> json) {
    return Bucket(
      name: json['name'],
      region: json['region'],
      creationDate: json['creationDate'] != null
          ? DateTime.parse(json['creationDate'])
          : null,
    );
  }

  Bucket copyWith({
    String? name,
    String? region,
    DateTime? creationDate,
  }) {
    return Bucket(
      name: name ?? this.name,
      region: region ?? this.region,
      creationDate: creationDate ?? this.creationDate,
    );
  }
}
