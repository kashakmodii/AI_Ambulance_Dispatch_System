import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'request_screen.dart';
import 'my_account_screen.dart';
import 'notifications_screen.dart';
import 'help_screen.dart';
import 'ambulance_list_screen.dart';
import 'book_on_call_screen.dart';
import 'my_rides_screen.dart';
import 'advance_booking_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class PatientDashboard extends StatefulWidget {
  final String patientName;

  const PatientDashboard({super.key, required this.patientName});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  int _currentIndex = 0;

  String? requestId;
  double? patientLat;
  double? patientLng;

  @override
  void initState() {
    super.initState();
    _fetchActiveRequest();
  }

  Future<Position?> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      return pos;
    } catch (e) {
      debugPrint('Error getting position: $e');
      return null;
    }
  }

  Future<void> _startQuickRequest() async {
    final pos = await _determinePosition();
    if (pos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to determine location.')));
      }
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final requestRef = await firestore.collection('requests').add({
        'name': widget.patientName,
        'contact': '',
        'location': {'lat': pos.latitude, 'lng': pos.longitude},
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // assign ambulance
      final assigned = await _assignNearestAmbulanceDashboard(
        requestRef.id,
        pos.latitude,
        pos.longitude,
      );

      if (assigned != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Ambulance assigned: ${assigned['hospital_name'] ?? 'Ambulance'}')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'No available ambulances found. Your request is pending.')));
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MapScreen(
            requestId: requestRef.id,
            patientLat: pos.latitude,
            patientLng: pos.longitude,
            patientName: widget.patientName,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error creating quick request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<Map<String, dynamic>?> _assignNearestAmbulanceDashboard(
      String requestId, double patientLat, double patientLng) async {
    final firestore = FirebaseFirestore.instance;
    try {
      final snapshot = await firestore
          .collection('ambulances')
          .where('status', isEqualTo: 'available')
          .get();

      if (snapshot.docs.isEmpty) return null;

      double shortest = double.infinity;
      QueryDocumentSnapshot? best;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final double ambLat = (data['latitude'] as num).toDouble();
        final double ambLng = (data['longitude'] as num).toDouble();

        final d =
            Geolocator.distanceBetween(patientLat, patientLng, ambLat, ambLng);
        if (d < shortest) {
          shortest = d;
          best = doc;
        }
      }

      if (best == null) return null;

      final ambId = best.id;
      final ambData = best.data() as Map<String, dynamic>;

      await firestore.collection('ambulances').doc(ambId).update({
        'status': 'assigned',
        'assigned_patient': requestId,
      });

      await firestore.collection('requests').doc(requestId).update({
        'assignedAmbulanceId': ambId,
        'ambulanceDetails': ambData,
        'status': 'assigned',
        'assigned_ambulance': ambData['hospital_name'] ?? '',
        'assigned_ambulance_lat': ambData['latitude'],
        'assigned_ambulance_lng': ambData['longitude'],
      });

      await firestore.collection('bookings').add({
        'requestId': requestId,
        'ambulanceId': ambId,
        'patientLat': patientLat,
        'patientLng': patientLng,
        'assignedAt': FieldValue.serverTimestamp(),
      });

      return ambData;
    } catch (e) {
      debugPrint('Error assigning ambulance: $e');
      return null;
    }
  }

  Future<void> _fetchActiveRequest() async {
    // Fetch the latest request from Firestore for this patient
    final snapshot = await FirebaseFirestore.instance
        .collection('requests')
        .where('name', isEqualTo: widget.patientName)
        .where('status', whereIn: ['pending', 'assigned'])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      final data = doc.data();
      setState(() {
        requestId = doc.id;
        patientLat = data['location']['lat'];
        patientLng = data['location']['lng'];
      });
    }
  }

  List<Widget> get _pages {
    return [
      requestId != null && patientLat != null && patientLng != null
          ? MapScreen(
              requestId: requestId!,
              patientLat: patientLat!,
              patientLng: patientLng!,
              patientName: widget.patientName,
            )
          : _buildHomeView(),
      RequestScreen(),
    ];
  }

  Widget _buildHomeView() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ====== Header Section ======
            _buildHeaderSection(),

            const SizedBox(height: 28),

            // ====== Emergency Action Section ======
            _buildEmergencySection(),

            const SizedBox(height: 24),

            // ====== Active Request Card ======
            _buildActiveRequestCard(),

            const SizedBox(height: 24),

            // ====== Quick Services Grid ======
            _buildQuickServicesSection(),

            const SizedBox(height: 24),

            // ====== Nearby Ambulances Section ======
            _buildNearbyAmbulancesSection(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back,',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.patientName.split(' ').first,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      NotificationsScreen(requestId: requestId ?? ''),
                ),
              );
            },
            icon: const Icon(Icons.notifications_outlined, size: 24),
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Confirm Emergency Request'),
                      content: Text(
                        'Request an ambulance immediately for ${widget.patientName}?\n\nYour location will be shared with the nearest ambulance.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Request Now'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    await _startQuickRequest();
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.local_hospital, color: Colors.white),
                      const SizedBox(width: 10),
                      const Text(
                        'Request Ambulance',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BookOnCallScreen()),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue, width: 1.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.phone, color: Colors.blue),
                      const SizedBox(width: 10),
                      const Text(
                        'Book on Call',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveRequestCard() {
    if (requestId == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600]),
                  const SizedBox(width: 10),
                  Text(
                    'No Active Request',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'You don\'t have any active emergency requests at the moment.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.red[50]!, Colors.red[100]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.location_on,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Active Request',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Request ID: ',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        Text(
                          requestId?.substring(0, 8) ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (patientLat != null && patientLng != null)
                      Text(
                        'Location: ${patientLat!.toStringAsFixed(4)}, ${patientLng!.toStringAsFixed(4)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.map, size: 18),
                      label:
                          const Text('Track', style: TextStyle(fontSize: 13)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapScreen(
                              requestId: requestId!,
                              patientLat: patientLat ?? 0,
                              patientLng: patientLng ?? 0,
                              patientName: widget.patientName,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: const BorderSide(color: Colors.red, width: 1.5),
                      ),
                      icon: const Icon(Icons.info_outline,
                          size: 18, color: Colors.red),
                      label: const Text('Details',
                          style: TextStyle(fontSize: 13, color: Colors.red)),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickServicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Services',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildServiceCard(
                icon: Icons.calendar_today,
                label: 'Schedule',
                color: Colors.blue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdvanceBookingScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildServiceCard(
                icon: Icons.local_taxi,
                label: 'My Rides',
                color: Colors.green,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MyRidesScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildServiceCard(
                icon: Icons.help_outline,
                label: 'Help',
                color: Colors.orange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => HelpScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyAmbulancesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Nearby Ambulances',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AmbulanceListScreen()),
                );
              },
              child: Text(
                'View All',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AmbulanceListScreen()),
            );
          },
          child: Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [Colors.blue[50]!, Colors.blue[100]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_hospital,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ambulances Available',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap to view nearby options',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Patient Dashboard"),
        backgroundColor: Colors.red,
        centerTitle: true,
      ),
      drawer: _buildDrawer(),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.red,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"),
          BottomNavigationBarItem(
              icon: Icon(Icons.request_page), label: "Request"),
        ],
      ),
    );
  }

  Drawer _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.red),
            accountName: Text(widget.patientName),
            accountEmail: const Text("Patient"),
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
                    builder: (_) =>
                        MyAccountScreen(requestId: requestId ?? "")),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.phone),
            title: const Text("Book on Call"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => BookOnCallScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_taxi),
            title: const Text("My Ride"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => MyRidesScreen()));
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
                      builder: (_) => const AdvanceBookingScreen()));
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
                          NotificationsScreen(requestId: requestId ?? "")));
            },
          ),
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text("Help"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => HelpScreen()));
            },
          ),
        ],
      ),
    );
  }
}
