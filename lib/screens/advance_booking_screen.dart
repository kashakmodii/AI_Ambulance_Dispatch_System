import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

class AdvanceBookingScreen extends StatefulWidget {
  const AdvanceBookingScreen({super.key});

  @override
  State<AdvanceBookingScreen> createState() => _AdvanceBookingScreenState();
}

class _AdvanceBookingScreenState extends State<AdvanceBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupC = TextEditingController();
  final _dropC = TextEditingController();
  final _noteC = TextEditingController();

  LatLng? _pickupLatLng;
  LatLng? _dropLatLng;

  String? _selectedAmbulanceId;
  String _selectedAmbulanceName = "Auto-assign nearest";

  bool _saving = false;
  double? _distanceKm;
  double? _etaMin;
  double? _cost;

  DateTime? _scheduledAt;

  List<Map<String, dynamic>> _pickupSuggestions = [];
  List<Map<String, dynamic>> _dropSuggestions = [];
  Timer? _debounce;

  static const double averageSpeedKmph = 40;
  static const double baseFare = 150;
  static const double perKm = 25;

  @override
  void dispose() {
    _pickupC.dispose();
    _dropC.dispose();
    _noteC.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ==================== OSM autocomplete ====================
  Future<void> _searchAddress(String query, bool isPickup) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final url = Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5');
        final response =
            await http.get(url, headers: {'User-Agent': 'FlutterApp'});
        final data = jsonDecode(response.body) as List<dynamic>;
        final suggestions = data
            .map((e) => {
                  'display_name': e['display_name'],
                  'lat': double.parse(e['lat']),
                  'lon': double.parse(e['lon']),
                })
            .toList();

        if (!mounted) return;

        setState(() {
          if (isPickup) {
            _pickupSuggestions = suggestions;
          } else {
            _dropSuggestions = suggestions;
          }
        });
      } catch (_) {}
    });
  }

  // ==================== Ambulance assignment ====================
  Future<void> _assignNearestAmbulance() async {
    if (_pickupLatLng == null || _dropLatLng == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('ambulances')
        .where('status', isEqualTo: 'available')
        .get();

    if (snapshot.docs.isEmpty) return;

    final distanceCalc = const Distance();
    double minDist = double.infinity;
    Map<String, dynamic>? nearestAmb;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final lat = data['latitude'];
      final lng = data['longitude'];
      if (lat == null || lng == null) continue;

      final d = distanceCalc.as(
        LengthUnit.Kilometer,
        _pickupLatLng!,
        LatLng(lat.toDouble(), lng.toDouble()),
      );

      if (d < minDist) {
        minDist = d;
        nearestAmb = {
          'id': doc.id,
          'name': data['hospital_name'] ?? 'Ambulance',
          'latitude': lat.toDouble(),
          'longitude': lng.toDouble(),
        };
      }
    }

    if (nearestAmb != null) {
      setState(() {
        _selectedAmbulanceId = nearestAmb!['id'];
        _selectedAmbulanceName = nearestAmb['name'];
        _distanceKm = minDist;

        _etaMin = (minDist / averageSpeedKmph) * 60;
        _cost = baseFare + perKm * minDist;
      });
    }
  }

  // ==================== Pick Date & Time ====================
  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      initialDate: now,
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))),
    );
    if (time == null) return;

    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // ==================== Submit booking ====================
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickupLatLng == null || _dropLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select pickup and drop location')));
      return;
    }
    if (_scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select date & time')));
      return;
    }

    setState(() => _saving = true);

    try {
      final bookingDoc =
          await FirebaseFirestore.instance.collection('bookings').add({
        'pickupAddress': _pickupC.text.trim(),
        'pickupLat': _pickupLatLng!.latitude,
        'pickupLng': _pickupLatLng!.longitude,
        'dropAddress': _dropC.text.trim(),
        'dropLat': _dropLatLng!.latitude,
        'dropLng': _dropLatLng!.longitude,
        'note': _noteC.text.trim(),
        'status': 'scheduled',
        'scheduledAt': Timestamp.fromDate(_scheduledAt!),
        'createdAt': FieldValue.serverTimestamp(),
        'ambulanceId': _selectedAmbulanceId,
        'etaMinutes': _etaMin,
        'cost': _cost,
      });

      if (_selectedAmbulanceId != null) {
        final assignedAt = DateTime.now();
        await FirebaseFirestore.instance
            .collection('ambulances')
            .doc(_selectedAmbulanceId)
            .update({
          'status': 'assigned',
          'assignedAt': Timestamp.fromDate(assignedAt),
          'assignedBooking': bookingDoc.id,
        });

        Future.delayed(Duration(minutes: (_etaMin! * 2).toInt()), () async {
          final ambSnap = await FirebaseFirestore.instance
              .collection('ambulances')
              .doc(_selectedAmbulanceId)
              .get();
          if (ambSnap.exists) {
            final data = ambSnap.data();
            if (data?['assignedBooking'] == bookingDoc.id) {
              await FirebaseFirestore.instance.collection('ambulances').doc(
                  _selectedAmbulanceId).update({'status': 'available', 'assignedBooking': null});
            }
          }
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip scheduled successfully')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    final dtStr = _scheduledAt == null
        ? 'Pick date & time'
        : DateFormat.yMMMd().add_jm().format(_scheduledAt!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Advance Booking'),
        backgroundColor: Colors.redAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Pickup
                  TextFormField(
                    controller: _pickupC,
                    decoration: const InputDecoration(
                      labelText: 'Pickup Address',
                      prefixIcon: Icon(Icons.my_location),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _searchAddress(v, true),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  if (_pickupSuggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _pickupSuggestions.length,
                        itemBuilder: (context, i) {
                          final s = _pickupSuggestions[i];
                          return ListTile(
                            title: Text(s['display_name']),
                            onTap: () {
                              setState(() {
                                _pickupC.text = s['display_name'];
                                _pickupLatLng = LatLng(s['lat'], s['lon']);
                                _pickupSuggestions = [];
                                _assignNearestAmbulance();
                              });
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Drop
                  TextFormField(
                    controller: _dropC,
                    decoration: const InputDecoration(
                      labelText: 'Drop Address',
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _searchAddress(v, false),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  if (_dropSuggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _dropSuggestions.length,
                        itemBuilder: (context, i) {
                          final s = _dropSuggestions[i];
                          return ListTile(
                            title: Text(s['display_name']),
                            onTap: () {
                              setState(() {
                                _dropC.text = s['display_name'];
                                _dropLatLng = LatLng(s['lat'], s['lon']);
                                _dropSuggestions = [];
                                _assignNearestAmbulance();
                              });
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Notes
                  TextFormField(
                    controller: _noteC,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.note_alt),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),

                  // Date & Time
                  ListTile(
                    onTap: _pickDateTime,
                    leading: const Icon(Icons.calendar_today),
                    title: Text('Scheduled Date & Time'),
                    subtitle: Text(dtStr),
                  ),
                  const SizedBox(height: 12),

                  // Ambulance Info
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.local_hospital),
                    title: Text('Ambulance: $_selectedAmbulanceName'),
                    subtitle: _distanceKm != null
                        ? Text(
                            'Distance: ${_distanceKm!.toStringAsFixed(2)} km, ETA: ${_etaMin!.toStringAsFixed(1)} min, Cost: ₹${_cost!.toStringAsFixed(0)}')
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                      label: Text(_saving ? 'Scheduling...' : 'Schedule Trip'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
