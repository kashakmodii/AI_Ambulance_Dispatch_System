import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

class NotificationsScreen extends StatelessWidget {
  final String requestId;

  const NotificationsScreen({super.key, required this.requestId});

  Future<void> _autoUpdateStatusIfCompleted(
      Map<String, dynamic> data, String requestId) async {
    final assignedAt = (data['assignedAt'] as Timestamp?)?.toDate();
    final etaMinutes = data['etaMinutes'] != null
        ? (data['etaMinutes'] as num).toDouble()
        : null;
    final currentStatus = data['status'];

    if (assignedAt != null &&
        etaMinutes != null &&
        currentStatus == 'assigned') {
      final minutesPassed = DateTime.now().difference(assignedAt).inMinutes;

      // After arrival time * 2, mark as available
      if (minutesPassed >= etaMinutes * 2) {
        final assignedAmb = data['assigned_ambulance'];
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(requestId)
            .update({
          'status': 'available',
          'completedAt': DateTime.now(),
        });

        if (assignedAmb != null) {
          final ambRef = await FirebaseFirestore.instance
              .collection('ambulances')
              .where('hospital_name', isEqualTo: assignedAmb)
              .limit(1)
              .get();

          if (ambRef.docs.isNotEmpty) {
            await ambRef.docs.first.reference.update({
              'status': 'available',
              'assigned_patient': null,
            });
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Status'),
        backgroundColor: Colors.redAccent,
      ),
      body: requestId.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No Active Request',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You don\'t have any active emergency requests.',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('requests')
                  .doc(requestId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(
                      child: Text('No data found for this request.'));
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;

                // Automatically check and update ambulance status
                _autoUpdateStatusIfCompleted(data, requestId);

                // Use assigned ambulance info
                final ambulanceName =
                    data['assigned_ambulance'] ?? 'Not assigned';
                final ambLat =
                    (data['assigned_ambulance_lat'] as num?)?.toDouble();
                final ambLng =
                    (data['assigned_ambulance_lng'] as num?)?.toDouble();

                final assignedAt = (data['assignedAt'] as Timestamp?)?.toDate();
                final arrivedAt = (data['arrivedAt'] as Timestamp?)?.toDate();
                final completedAt =
                    (data['completedAt'] as Timestamp?)?.toDate();

                String status = data['status'] ?? 'available';

                // Distance / ETA / Cost
                double? distanceKm;
                double? etaMin;
                double? cost;

                final loc = data['location'] as Map<String, dynamic>? ?? {};
                final patLat = loc['lat'] ?? loc['latitude'];
                final patLng = loc['lng'] ?? loc['longitude'];

                if (ambLat != null &&
                    ambLng != null &&
                    patLat != null &&
                    patLng != null) {
                  final meters = Geolocator.distanceBetween(
                    ambLat,
                    ambLng,
                    (patLat as num).toDouble(),
                    (patLng as num).toDouble(),
                  );

                  distanceKm = meters / 1000;
                  etaMin = (distanceKm / 40) * 60; // 40 km/h average speed
                  const baseFare = 100.0;
                  const perKm = 20.0;
                  cost = baseFare + perKm * distanceKm;
                }

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['name'] ?? 'Patient',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text('Emergency: ${data['emergencyType'] ?? '-'}'),
                          const Divider(height: 24),
                          Text(
                            'Ambulance Details',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('Hospital: $ambulanceName'),
                          if (ambLat != null && ambLng != null)
                            Text('Location: $ambLat , $ambLng'),
                          const Divider(height: 24),
                          if (assignedAt != null)
                            Text(
                                'Assigned at: ${DateFormat.yMMMd().add_jm().format(assignedAt)}'),
                          if (arrivedAt != null)
                            Text(
                                'Arrived at: ${DateFormat.yMMMd().add_jm().format(arrivedAt)}'),
                          if (completedAt != null)
                            Text(
                                'Completed at: ${DateFormat.yMMMd().add_jm().format(completedAt)}'),
                          const SizedBox(height: 12),
                          Text(
                            'Status: $status',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (distanceKm != null) ...[
                            const SizedBox(height: 8),
                            Text(
                                'Distance: ${distanceKm.toStringAsFixed(2)} km'),
                            Text(
                                'Estimated Arrival: ${etaMin!.toStringAsFixed(1)} min'),
                            Text('Cost: ₹${cost!.toStringAsFixed(0)}'),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
