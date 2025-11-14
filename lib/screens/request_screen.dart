import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'map_screen.dart';

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _emergencyController = TextEditingController();

  bool _isLoading = false;

  Position? _currentPosition;
  String? _selectedEmergency;

  final List<String> _emergencyTypes = [
    "Heart Attack",
    "Accident",
    "Burn Injury",
    "Stroke",
    "Respiratory Issue",
    "Other"
  ];

  @override
  void initState() {
    super.initState();
    _fetchLiveLocation();
  }

  Future<void> _fetchLiveLocation() async {
    try {
      setState(() => _isLoading = true);
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception("Location services are disabled.");
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception("Location permission denied.");
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception("Location permissions permanently denied.");
      }
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = pos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate() || _currentPosition == null) return;
    if (_contactController.text.trim().length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please enter a valid 10-digit phone number")),
      );
      return;
    }

    setState(() => _isLoading = true);

    await _saveRequestToFirestore(); // Save + assign ambulance
  }

  Future<void> _saveRequestToFirestore() async {
    try {
      String emergencyValue = _selectedEmergency == "Other"
          ? _emergencyController.text
          : _selectedEmergency ?? "";

      // 1. Save request
      DocumentReference requestRef =
          await FirebaseFirestore.instance.collection('requests').add({
        "name": _nameController.text,
        "age": int.parse(_ageController.text),
        "contact": _contactController.text,
        "emergencyType": emergencyValue,
        "location": {
          "lat": _currentPosition!.latitude,
          "lng": _currentPosition!.longitude,
        },
        "status": "pending",
        "createdAt": FieldValue.serverTimestamp(),
      });

      // 2. Find nearest ambulance and assign
      await _assignNearestAmbulance(
        requestId: requestRef.id,
        patientLat: _currentPosition!.latitude,
        patientLng: _currentPosition!.longitude,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MapScreen(
              requestId: requestRef.id,
              patientLat: _currentPosition!.latitude,
              patientLng: _currentPosition!.longitude,
              patientName: _nameController.text,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _assignNearestAmbulance({
    required String requestId,
    required double patientLat,
    required double patientLng,
  }) async {
    final firestore = FirebaseFirestore.instance;

    try {
      // Get available ambulances
      QuerySnapshot snapshot = await firestore
          .collection('ambulances')
          .where('status', isEqualTo: 'available')
          .get();

      if (snapshot.docs.isEmpty) {
        print("❌ No available ambulances found.");
        return;
      }

      double shortestDistance = double.infinity;
      DocumentSnapshot? nearestAmbulance;

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final double ambLat = data['latitude'];
        final double ambLng = data['longitude'];

        double distance = Geolocator.distanceBetween(
          patientLat,
          patientLng,
          ambLat,
          ambLng,
        );

        if (distance < shortestDistance) {
          shortestDistance = distance;
          nearestAmbulance = doc;
        }
      }

      if (nearestAmbulance == null) return;

      final ambulanceId = nearestAmbulance.id;
      final ambulanceData = nearestAmbulance.data() as Map<String, dynamic>;

      // Update ambulance status
      await firestore.collection('ambulances').doc(ambulanceId).update({
        'status': 'assigned',
      });

      // Update request with ambulance details
      await firestore.collection('requests').doc(requestId).update({
        'assignedAmbulanceId': ambulanceId,
        'ambulanceDetails': ambulanceData,
        'status': 'assigned',
      });

      // Create booking record
      await firestore.collection('bookings').add({
        'requestId': requestId,
        'ambulanceId': ambulanceId,
        'patientLat': patientLat,
        'patientLng': patientLng,
        'assignedAt': FieldValue.serverTimestamp(),
      });

      print("✅ Nearest ambulance assigned: $ambulanceId");

      // Show user feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Ambulance assigned: ${ambulanceData['hospital_name']}")),
        );
      }
    } catch (e) {
      print("🔥 Error assigning ambulance: $e");
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: inputType,
      enabled: enabled,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.red),
        labelText: label,
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey[200],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: validator ?? (value) => value!.isEmpty ? "Enter $label" : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("🚑 Request Ambulance"),
        backgroundColor: Colors.red,
        centerTitle: true,
      ),
      body: _isLoading && _currentPosition == null
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Card(
                        color: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              const Text("Patient Information",
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                              const SizedBox(height: 16),
                              _buildTextField(
                                  controller: _nameController,
                                  label: "Full Name",
                                  icon: Icons.person),
                              const SizedBox(height: 12),
                              _buildTextField(
                                  controller: _ageController,
                                  label: "Age",
                                  icon: Icons.cake,
                                  inputType: TextInputType.number),
                              const SizedBox(height: 12),
                              _buildTextField(
                                  controller: _contactController,
                                  label: "Mobile Number",
                                  icon: Icons.phone,
                                  inputType: TextInputType.phone),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.warning,
                                      color: Colors.red),
                                  labelText: "Emergency Type",
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                value: _selectedEmergency,
                                items: _emergencyTypes
                                    .map((e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ))
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedEmergency = value;
                                    if (value != "Other") {
                                      _emergencyController.text = value ?? "";
                                    } else {
                                      _emergencyController.clear();
                                    }
                                  });
                                },
                                validator: (value) =>
                                    value == null ? "Select emergency" : null,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                  controller: _emergencyController,
                                  label: "Emergency Details (if Other)",
                                  icon: Icons.edit,
                                  enabled: _selectedEmergency == "Other"),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              color: _currentPosition != null
                                  ? Colors.green
                                  : Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                            _currentPosition != null
                                ? "Location detected (Lat: ${_currentPosition!.latitude.toStringAsFixed(4)}, Lng: ${_currentPosition!.longitude.toStringAsFixed(4)})"
                                : "Detecting location...",
                            style: const TextStyle(fontSize: 14),
                          )),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitRequest,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text(
                                  "Submit Emergency Request",
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
