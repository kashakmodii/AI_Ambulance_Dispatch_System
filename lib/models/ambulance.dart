class Ambulance {
  final String id;
  final double? latitude;
  final double? longitude;
  final String? status;
  double? distance;

  Ambulance({
    required this.id,
    this.latitude,
    this.longitude,
    this.status,
    this.distance,
  });

  factory Ambulance.fromFirestore(Map<String, dynamic> data, String id) {
    return Ambulance(
      id: id,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      status: data['status'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
    };
  }
}
