import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MyAccountScreen extends StatelessWidget {
  final String requestId;
  const MyAccountScreen({super.key, required this.requestId});

  @override
  Widget build(BuildContext context) {
    final docRef =
        FirebaseFirestore.instance.collection('requests').doc(requestId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Details'),
        backgroundColor: Colors.redAccent,
        centerTitle: true,
        elevation: 4,
        shadowColor: Colors.redAccent.withAlpha((0.5 * 255).round()),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Text(
              'Error: ${snap.error}',
              style: const TextStyle(color: Colors.redAccent),
            ));
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
                child: Text(
              'No details found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ));
          }

          final data = snap.data!.data()!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Profile Avatar
                Center(
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.redAccent,
                    child: Text(
                      (data['name']?.toString().isNotEmpty == true
                              ? data['name'].toString().characters.first
                              : 'U')
                          .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  data['name'] ?? 'Unknown Patient',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 24),

                // Patient Info Section
                _sectionHeader('Patient Information'),
                _infoTile('Contact', data['contact'], icon: Icons.phone),
                _infoTile('Age', data['age'], icon: Icons.cake),
                _infoTile('Emergency Type', data['emergencyType'],
                    icon: Icons.warning_amber_rounded),
                _infoTile('Status', data['status'], icon: Icons.verified),
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  // Section Header
  Widget _sectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          title,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.redAccent),
        ),
      ),
    );
  }

  // Info Card Tile
  Widget _infoTile(String label, dynamic value, {IconData? icon}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: icon != null
            ? CircleAvatar(
                backgroundColor:
                    Colors.redAccent.withAlpha((0.1 * 255).round()),
                child: Icon(icon, color: Colors.redAccent),
              )
            : null,
        title: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.black87)),
        subtitle: Text(
          value != null && value.toString().isNotEmpty ? value.toString() : '-',
          style: const TextStyle(color: Colors.black54),
        ),
      ),
    );
  }
}
