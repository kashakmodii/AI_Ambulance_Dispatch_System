class PatientRequest {
  final String requestId;
  final String name;
  final double latitude;
  final double longitude;
  final String status; // pending, assigned, completed

  PatientRequest({
    required this.requestId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.status,
  });

  factory PatientRequest.fromMap(Map<String, dynamic> data, String id) {
    return PatientRequest(
      requestId: id,
      name: data['name'] ?? '',
      latitude: (data['latitude'] ?? 0).toDouble(),
      longitude: (data['longitude'] ?? 0).toDouble(),
      status: data['status'] ?? 'pending',
    );
  }
}
