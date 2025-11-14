import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MyRidesScreen extends StatelessWidget {
  const MyRidesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final requestsRef = FirebaseFirestore.instance.collection('requests');

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rides'),
        backgroundColor: Colors.redAccent,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: requestsRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Error loading rides: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No rides found'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();

              final type = data['emergencyType'] ?? '';
              final createdAt = data['createdAt'] is Timestamp
                  ? (data['createdAt'] as Timestamp).toDate()
                  : null;

              // Dynamic status computation
              final assignedAt = data['assignedAt'] != null
                  ? (data['assignedAt'] as Timestamp).toDate()
                  : null;
              final etaMinutes = data['etaMinutes'] != null
                  ? (data['etaMinutes'] as num).toDouble()
                  : null;

              String status = data['status'] ?? 'available';
              if (assignedAt != null && etaMinutes != null) {
                final minutesPassed =
                    DateTime.now().difference(assignedAt).inMinutes;
                status =
                    minutesPassed >= etaMinutes * 2 ? 'available' : 'assigned';
              }

              // ----------------- Hospital Name Logic -----------------
              Future<String> getHospitalName() async {
                // Check if hospital field exists directly in request
                if ((data['hospital_name'] ?? '').toString().isNotEmpty) {
                  return data['hospital_name'];
                }
                if ((data['hospitalName'] ?? '').toString().isNotEmpty) {
                  return data['hospitalName'];
                }

                // If linked with ambulanceId, fetch from ambulance doc
                if (data['ambulanceId'] != null &&
                    data['ambulanceId'].toString().isNotEmpty) {
                  final ambSnap = await FirebaseFirestore.instance
                      .collection('ambulances')
                      .doc(data['ambulanceId'])
                      .get();
                  return ambSnap.data()?['hospital_name'] ??
                      ambSnap.data()?['hospitalName'] ??
                      'Unknown hospital';
                }

                return 'Unknown hospital';
              }
              // -------------------------------------------------------

              return FutureBuilder<String>(
                future: getHospitalName(),
                builder: (context, snap) {
                  final hospital = snap.data ?? 'Loading...';

                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      title: Text(hospital),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status: $status'),
                          if (type.isNotEmpty) Text('Type: $type'),
                          if (createdAt != null)
                            Text(
                              'Requested: ${createdAt.toLocal()}',
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
