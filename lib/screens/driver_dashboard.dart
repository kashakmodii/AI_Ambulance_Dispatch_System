// lib/screens/driver_dashboard.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class DriverDashboard extends StatefulWidget {
  final String driverName;
  final String ambulanceId;

  const DriverDashboard({
    super.key,
    required this.driverName,
    required this.ambulanceId,
  });

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  Map<String, dynamic> _ambulanceData = {};

  @override
  void initState() {
    super.initState();
    _fetchAmbulanceData();
  }

  Future<void> _fetchAmbulanceData() async {
    if (widget.ambulanceId == 'unassigned') return;

    final doc = await FirebaseFirestore.instance
        .collection('ambulances')
        .doc(widget.ambulanceId)
        .get();

    if (doc.exists) {
      setState(() => _ambulanceData = doc.data()!);
    }
  }

  // Robust extraction of latitude/longitude from ambulance document data
  LatLng? _extractAmbLatLng(Map<String, dynamic> data) {
    try {
      // If there's a nested location/geo object
      final loc =
          data['location'] ?? data['coords'] ?? data['position'] ?? data['geo'];
      if (loc != null) {
        // Firestore GeoPoint
        try {
          final lat = (loc['lat'] ?? loc['latitude']) as num?;
          final lng = (loc['lng'] ?? loc['longitude']) as num?;
          if (lat != null && lng != null)
            return LatLng(lat.toDouble(), lng.toDouble());
        } catch (_) {}

        // GeoPoint object (has .latitude/.longitude)
        try {
          final dyn = loc;
          final lat = dyn.latitude as num?;
          final lng = dyn.longitude as num?;
          if (lat != null && lng != null)
            return LatLng(lat.toDouble(), lng.toDouble());
        } catch (_) {}
      }

      // Direct fields on the ambulance doc
      final latVal = (data['latitude'] ?? data['lat']) as num?;
      final lngVal = (data['longitude'] ?? data['lng']) as num?;
      if (latVal != null && lngVal != null)
        return LatLng(latVal.toDouble(), lngVal.toDouble());

      // Some docs might store coordinates under different keys
      if (data.containsKey('coordinates')) {
        try {
          final coords = data['coordinates'];
          final lat = (coords[1] ?? coords['lat']) as num?;
          final lng = (coords[0] ?? coords['lng']) as num?;
          if (lat != null && lng != null)
            return LatLng(lat.toDouble(), lng.toDouble());
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  // Accept a pending request
  Future<void> _acceptRequest(String requestId) async {
    if (_ambulanceData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ambulance not assigned yet.")),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
        'status': 'assigned',
        'assignedAmbulanceId': widget.ambulanceId,
        // Use ambulance's hospital/name for assigned_ambulance so it's accurate
        'assigned_ambulance': (_ambulanceData['hospital_name'] ??
            _ambulanceData['name'] ??
            widget.driverName),
        // Ensure lat/lng fields use the common keys if present
        'assigned_ambulance_lat':
            _ambulanceData['latitude'] ?? _ambulanceData['lat'] ?? 0,
        'assigned_ambulance_lng':
            _ambulanceData['longitude'] ?? _ambulanceData['lng'] ?? 0,
        'assignedAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request accepted successfully.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error accepting request: $e")),
      );
    }
  }

  // Complete a trip
  Future<void> _completeRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });

      // Mark ambulance as available.
      // First prefer the driver's assigned ambulance ID (if valid), otherwise try to find ambulance by assigned_patient
      if (widget.ambulanceId.isNotEmpty && widget.ambulanceId != 'unassigned') {
        try {
          await FirebaseFirestore.instance
              .collection('ambulances')
              .doc(widget.ambulanceId)
              .update({
            'status': 'available',
            'assigned_patient': null,
          });
        } catch (_) {}
      }

      // Also clear any ambulance that still references this requestId (covers other assignment flows)
      try {
        final ambs = await FirebaseFirestore.instance
            .collection('ambulances')
            .where('assigned_patient', isEqualTo: requestId)
            .get();
        for (final doc in ambs.docs) {
          await doc.reference
              .update({'status': 'available', 'assigned_patient': null});
        }
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text("Trip marked as completed. Ambulance is now available.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error completing trip: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Driver Dashboard - ${widget.driverName}"),
        backgroundColor: Colors.blueAccent,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .where('status', whereIn: ['pending', 'assigned']).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No active or pending requests.",
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          final requests = snapshot.data!.docs;

          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final data = requests[index].data() as Map<String, dynamic>;
              final requestId = requests[index].id;
              final patientName = data['name'] ?? "Unknown";
              final contact = data['contact'] ?? "N/A";
              final emergencyType = data['emergencyType'] ?? "Unknown";
              final status = data['status'] ?? "pending";

              final location = data['location'] as Map<String, dynamic>? ?? {};
              final patientLat = (location['lat'] ?? 0).toDouble();
              final patientLng = (location['lng'] ?? 0).toDouble();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 3,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  title: Text(
                    "Patient: $patientName",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("Contact: $contact"),
                      Text("Emergency: $emergencyType"),
                      Text("Status: $status"),
                      const SizedBox(height: 4),
                      Text(
                          "Assigned Ambulance: ${data['assigned_ambulance'] ?? 'N/A'}"),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'accept') {
                        await _acceptRequest(requestId);
                      } else if (value == 'map') {
                        // Check if ambulance ID is valid
                        if (widget.ambulanceId.isEmpty ||
                            widget.ambulanceId == 'unassigned') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Ambulance not assigned to this driver.'),
                            ),
                          );
                          return;
                        }

                        // Get current ambulance location from Firestore
                        try {
                          final ambDoc = await FirebaseFirestore.instance
                              .collection('ambulances')
                              .doc(widget.ambulanceId)
                              .get();

                          if (ambDoc.exists) {
                            final ambData =
                                ambDoc.data() as Map<String, dynamic>;
                            final ambPos = _extractAmbLatLng(ambData);
                            if (ambPos == null) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Ambulance coordinates not found in document.'),
                                  ),
                                );
                              }
                            } else {
                              final driverLat = ambPos.latitude;
                              final driverLng = ambPos.longitude;

                              if (mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DriverMapView(
                                      patientLat: patientLat,
                                      patientLng: patientLng,
                                      requestId: requestId,
                                      patientName: patientName,
                                      driverLat: driverLat,
                                      driverLng: driverLng,
                                    ),
                                  ),
                                );
                              }
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Ambulance not found in database. ID: ${widget.ambulanceId}'),
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error fetching ambulance: $e'),
                              ),
                            );
                          }
                        }
                      } else if (value == 'complete') {
                        await _completeRequest(requestId);
                      }
                    },
                    itemBuilder: (context) => [
                      if (status == 'pending')
                        const PopupMenuItem(
                          value: 'accept',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Text("Accept Request"),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'map',
                        child: Row(
                          children: [
                            Icon(Icons.map, color: Colors.blue),
                            SizedBox(width: 8),
                            Text("View on Map"),
                          ],
                        ),
                      ),
                      if (status == 'assigned')
                        const PopupMenuItem(
                          value: 'complete',
                          child: Row(
                            children: [
                              Icon(Icons.done_all, color: Colors.orange),
                              SizedBox(width: 8),
                              Text("Mark Completed"),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============== DRIVER MAP VIEW ==============
class DriverMapView extends StatefulWidget {
  final double patientLat;
  final double patientLng;
  final double driverLat;
  final double driverLng;
  final String requestId;
  final String patientName;

  const DriverMapView({
    Key? key,
    required this.patientLat,
    required this.patientLng,
    required this.driverLat,
    required this.driverLng,
    required this.requestId,
    required this.patientName,
  }) : super(key: key);

  @override
  State<DriverMapView> createState() => _DriverMapViewState();
}

class _DriverMapViewState extends State<DriverMapView> {
  late MapController _mapController;
  late LatLng _driverPos;
  late LatLng _patientPos;
  List<LatLng> _routePoints = [];
  double _distanceKm = 0;
  double _etaMinutes = 0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _driverPos = LatLng(widget.driverLat, widget.driverLng);
    _patientPos = LatLng(widget.patientLat, widget.patientLng);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bounds = LatLngBounds.fromPoints([_driverPos, _patientPos]);
      _mapController.fitBounds(
        bounds,
        options: const FitBoundsOptions(padding: EdgeInsets.all(100)),
      );
      _fetchRoute();
    });
  }

  Future<void> _fetchRoute() async {
    try {
      final url = "https://router.project-osrm.org/route/v1/driving/"
          "${_driverPos.longitude},${_driverPos.latitude};${_patientPos.longitude},${_patientPos.latitude}"
          "?overview=full&geometries=geojson";

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords =
            data["routes"][0]["geometry"]["coordinates"] as List<dynamic>;
        final distance =
            (data["routes"][0]["distance"] as num).toDouble() / 1000; // km
        final duration =
            (data["routes"][0]["duration"] as num).toDouble() / 60; // minutes

        setState(() {
          _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList();
          _distanceKm = distance;
          _etaMinutes = duration;
        });
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
    }
  }

  Future<void> _openNavigation() async {
    final googleMapsUrl =
        'https://www.google.com/maps/dir/${_driverPos.latitude},${_driverPos.longitude}/'
        '${_patientPos.latitude},${_patientPos.longitude}/?travelmode=driving';

    if (await canLaunchUrl(Uri.parse(googleMapsUrl))) {
      await launchUrl(Uri.parse(googleMapsUrl),
          mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not open navigation. Please install Google Maps.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigate to Patient'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _driverPos,
              zoom: 14.0,
              maxZoom: 19.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.app',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: Colors.green,
                    ),
                  ],
                )
              else
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_driverPos, _patientPos],
                      strokeWidth: 4,
                      color: Colors.blue,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Driver position
                  Marker(
                    point: _driverPos,
                    width: 100,
                    height: 100,
                    builder: (ctx) => Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 3,
                                offset: Offset(1, 1),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Your Position',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Icon(
                          Icons.local_hospital,
                          color: Colors.blue,
                          size: 50,
                        ),
                      ],
                    ),
                  ),
                  // Patient position
                  Marker(
                    point: _patientPos,
                    width: 100,
                    height: 100,
                    builder: (ctx) => Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 3,
                                offset: Offset(1, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            widget.patientName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 50,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Patient: ${widget.patientName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Request ID: ${widget.requestId.substring(0, 8)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (_distanceKm > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Distance: ${_distanceKm.toStringAsFixed(1)} km',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[700]),
                          ),
                          Text(
                            'ETA: ${_etaMinutes.toStringAsFixed(0)} min',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        minimumSize: const Size(double.infinity, 40),
                      ),
                      icon: const Icon(Icons.navigation),
                      label: const Text('Open Navigation'),
                      onPressed: _openNavigation,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
