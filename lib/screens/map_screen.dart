import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'my_account_screen.dart';
import 'book_on_call_screen.dart';
import 'notifications_screen.dart';
import 'help_screen.dart';
import 'my_rides_screen.dart';
import 'advance_booking_screen.dart';

class MapScreen extends StatefulWidget {
  final double patientLat;
  final double patientLng;
  final String requestId;
  final String patientName;

  const MapScreen({
    Key? key,
    required this.patientLat,
    required this.patientLng,
    required this.requestId,
    required this.patientName,
  }) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  String locationName = "Fetching address...";
  late LatLng _patientPos;

  LatLng? _nearestAmbPos;
  String _nearestAmbName = "Searching...";
  double? _nearestAmbDistanceMeters;
  bool _alertShown = false;

  String _userName = "User Name";
  String _userMobile = "0000000000";

  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _patientPos = LatLng(widget.patientLat, widget.patientLng);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _mapController.move(_patientPos, 17.0);
      await _fetchPlaceName(_patientPos.latitude, _patientPos.longitude);
      await _maybeFixWithLiveGps();
      await _fetchNearestAmbulance();
      await _fetchUserFromRequest();
    });
  }

  Future<void> _maybeFixWithLiveGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final live = LatLng(pos.latitude, pos.longitude);
      final d = const Distance().as(LengthUnit.Meter, _patientPos, live);

      if (d > 100) {
        _patientPos = live;
        if (!mounted) return;
        _mapController.move(_patientPos, 17.0);
        await _fetchPlaceName(_patientPos.latitude, _patientPos.longitude);
      }
    } catch (_) {}
  }

  Future<void> _fetchPlaceName(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'FlutterApp'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          locationName = data['display_name'] ?? "Unknown location";
        });
      } else {
        setState(() {
          locationName = "Could not fetch location name";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        locationName = "Could not fetch location name";
      });
    }
  }

  LatLng? _extractLatLngFromAmbData(Map<String, dynamic> data) {
    try {
      if (data['latitude'] != null && data['longitude'] != null) {
        final lat = (data['latitude'] as num).toDouble();
        final lng = (data['longitude'] as num).toDouble();
        return LatLng(lat, lng);
      }
    } catch (e) {
      debugPrint("Error extracting ambulance location: $e");
    }
    return null;
  }

  Future<void> _fetchNearestAmbulance() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('ambulances').get();

      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        setState(() {
          _nearestAmbName = "No ambulances found";
          _nearestAmbPos = null;
          _nearestAmbDistanceMeters = null;
        });
        return;
      }

      final distanceCalc = const Distance();
      double minDistance = double.infinity;
      LatLng? bestPos;
      String bestName = '';

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] ?? 'available';
        final assignedPatient = data['assigned_patient'];

        if (status == 'assigned' && assignedPatient != widget.requestId)
          continue;

        final ambPos = _extractLatLngFromAmbData(
          Map<String, dynamic>.from(data),
        );
        if (ambPos == null) continue;

        final d = distanceCalc.as(LengthUnit.Meter, _patientPos, ambPos);

        if (d < minDistance) {
          minDistance = d;
          bestPos = ambPos;
          bestName = (data['hospital_name'] as String?) ?? 'Ambulance';
        }
      }

      if (!mounted) return;

      setState(() {
        _nearestAmbPos = bestPos;
        _nearestAmbName = bestName;
        _nearestAmbDistanceMeters = minDistance.isFinite ? minDistance : null;
      });

      // ✅ Update Firestore so both Map and Notifications show same ambulance
      if (bestPos != null && bestName.isNotEmpty) {
        // Update request document with assigned ambulance info
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .update({
          'assigned_ambulance': bestName,
          'assigned_ambulance_lat': bestPos.latitude,
          'assigned_ambulance_lng': bestPos.longitude,
          'status': 'assigned',
        });

        // Update ambulance document
        final ambSnap = await FirebaseFirestore.instance
            .collection('ambulances')
            .where('hospital_name', isEqualTo: bestName)
            .limit(1)
            .get();

        if (ambSnap.docs.isNotEmpty) {
          await ambSnap.docs.first.reference.update({
            'status': 'assigned',
            'assigned_patient': widget.requestId,
          });
        }
      }

      if (bestPos != null && _nearestAmbDistanceMeters != null) {
        final bounds = LatLngBounds.fromPoints([_patientPos, bestPos]);
        Future.delayed(const Duration(milliseconds: 200), () {
          try {
            _mapController.fitBounds(
              bounds,
              options: const FitBoundsOptions(padding: EdgeInsets.all(60)),
            );
          } catch (_) {}
        });

        await _fetchRoute(_patientPos, bestPos);

        if (!_alertShown) {
          _alertShown = true;
          _showNearestAmbulanceAlert(
            name: _nearestAmbName,
            distanceMeters: _nearestAmbDistanceMeters!,
          );
        }

        // ✅ Auto-complete after ETA * 2
        final arrivalMinutes =
            (_nearestAmbDistanceMeters! / 1000) / 40 * 60; // 40 km/h
        Future.delayed(Duration(minutes: (arrivalMinutes * 2).toInt()),
            () async {
          try {
            await FirebaseFirestore.instance
                .collection('requests')
                .doc(widget.requestId)
                .update({
              'status': 'completed',
              'completedAt': DateTime.now(),
            });

            final ambSnap = await FirebaseFirestore.instance
                .collection('ambulances')
                .where('hospital_name', isEqualTo: _nearestAmbName)
                .limit(1)
                .get();

            if (ambSnap.docs.isNotEmpty) {
              await ambSnap.docs.first.reference.update({
                'status': 'available',
                'assigned_patient': null,
              });
            }
          } catch (e) {
            debugPrint("Error auto-completing ride: $e");
          }
        });
      }
    } catch (e, st) {
      print('Error fetching nearest ambulance: $e\n$st');
      if (!mounted) return;
      setState(() {
        _nearestAmbName = 'Error fetching ambulance';
        _nearestAmbPos = null;
        _nearestAmbDistanceMeters = null;
      });
    }
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    try {
      final url = "https://router.project-osrm.org/route/v1/driving/"
          "${start.longitude},${start.latitude};${end.longitude},${end.latitude}"
          "?overview=full&geometries=geojson";

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords =
            data["routes"][0]["geometry"]["coordinates"] as List<dynamic>;

        setState(() {
          _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList();
        });
      }
    } catch (_) {
      setState(() {
        _routePoints = [];
      });
    }
  }

  dynamic _getIn(Map<String, dynamic> map, String path) {
    dynamic cur = map;
    for (final part in path.split('.')) {
      if (cur is Map<String, dynamic> && cur.containsKey(part)) {
        cur = cur[part];
      } else {
        return null;
      }
    }
    return cur;
  }

  String? _pickString(Map<String, dynamic> map, List<String> paths) {
    for (final p in paths) {
      final v = _getIn(map, p);
      if (v == null) continue;
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is num) return v.toString();
    }
    return null;
  }

  Future<void> _fetchUserFromRequest() async {
    try {
      final col = FirebaseFirestore.instance.collection('requests');
      final docSnap = await col.doc(widget.requestId).get();
      Map<String, dynamic>? data = docSnap.exists ? docSnap.data() : null;

      if (data == null) return;

      final name = _pickString(data, [
            'name',
            'username',
            'fullName',
            'userName',
            'patientName',
            'contactName',
            'user.name',
            'user.fullName',
            'user.displayName',
          ]) ??
          widget.patientName;

      final phone = _pickString(data, [
        'contact',
        'mobile',
        'phone',
        'phoneNumber',
        'mobileNumber',
        'contactNumber',
        'number',
        'user.mobile',
        'user.phone',
        'user.phoneNumber',
        'user.contact',
      ]);

      String finalPhone = "0000000000";
      if (phone != null && phone.trim().isNotEmpty) {
        final sanitized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
        finalPhone = sanitized.isNotEmpty ? sanitized : phone;
      }

      if (!mounted) return;
      setState(() {
        _userName = name;
        _userMobile = finalPhone;
      });
    } catch (_) {}
  }

  void _showNearestAmbulanceAlert({
    required String name,
    required double distanceMeters,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Nearest Ambulance Found"),
        content: Text(
          "$name is ${(distanceMeters / 1000).toStringAsFixed(2)} km away.",
        ),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Ambulance'),
        backgroundColor: Colors.red,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.red),
              accountName: Text(_userName),
              accountEmail: Text(_userMobile),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.red),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text("My Account"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        MyAccountScreen(requestId: widget.requestId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone),
              title: const Text("Book on Call"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => BookOnCallScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_taxi),
              title: const Text("My Ride"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyRidesScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text("Advance Trip"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdvanceBookingScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text("Notifications"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        NotificationsScreen(requestId: widget.requestId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help),
              title: const Text("Help"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => HelpScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(center: _patientPos, zoom: 17.0, maxZoom: 19.0),
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
                ),
              if (_routePoints.isEmpty && _nearestAmbPos != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_patientPos, _nearestAmbPos!],
                      strokeWidth: 4,
                      color: Colors.red,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _patientPos,
                    width: 140,
                    height: 90,
                    builder: (ctx) => Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
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
                  if (_nearestAmbPos != null)
                    Marker(
                      point: _nearestAmbPos!,
                      width: 100,
                      height: 100,
                      builder: (ctx) => const Icon(
                        Icons.local_hospital,
                        color: Colors.blue,
                        size: 45,
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
              color: Colors.white,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "Request ID: ${widget.requestId}\n"
                  "Patient: ${widget.patientName}\n"
                  "Location: $locationName\n"
                  "Coordinates: (${_patientPos.latitude.toStringAsFixed(5)}, ${_patientPos.longitude.toStringAsFixed(5)})\n"
                  "Nearest Ambulance: $_nearestAmbName${_nearestAmbDistanceMeters != null ? " (${(_nearestAmbDistanceMeters! / 1000).toStringAsFixed(2)} km)" : ""}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
