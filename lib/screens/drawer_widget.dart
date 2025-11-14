import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'my_account_screen.dart';
import 'book_on_call_screen.dart';
import 'my_rides_screen.dart';
import 'advance_booking_screen.dart';
import 'notifications_screen.dart';
import 'help_screen.dart';

class DrawerWidget extends StatefulWidget {
  const DrawerWidget({super.key});

  @override
  State<DrawerWidget> createState() => _DrawerWidgetState();
}

class _DrawerWidgetState extends State<DrawerWidget> {
  String _userName = "User Name";
  String _userMobile = "0000000000";
  String? _latestRequestId;

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
    _fetchLatestRequest();
  }

  // Fetch current user info
  Future<void> _fetchUserInfo() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          setState(() {
            _userName = data['name'] ?? _userName;
            _userMobile = data['mobile'] ?? _userMobile;
          });
        }
      }
    } catch (e) {
      print("Error fetching user info: $e");
    }
  }

  // Fetch latest request ID for this user
  Future<void> _fetchLatestRequest() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final query = await FirebaseFirestore.instance
          .collection('requests')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        setState(() {
          _latestRequestId = query.docs.first.id;
        });
      }
    } catch (e) {
      print("Error fetching latest request: $e");
    }
  }

  // Navigate helper
  void _navigateIfRequest(String screenName, Widget screen) {
    if (_latestRequestId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => screen,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No active request found.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.redAccent),
            accountName: Text(_userName, style: const TextStyle(fontSize: 18)),
            accountEmail: Text(_userMobile, style: const TextStyle(fontSize: 14)),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Colors.redAccent),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.person, color: Colors.redAccent),
            title: const Text("My Account"),
            onTap: () {
              if (_latestRequestId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyAccountScreen(requestId: _latestRequestId!),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("No active request found.")),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.phone, color: Colors.redAccent),
            title: const Text("Book on Call"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BookOnCallScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_taxi, color: Colors.redAccent),
            title: const Text("My Ride"),
            onTap: () {
              _navigateIfRequest(
                "My Ride",
                MyRidesScreen(),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today, color: Colors.redAccent),
            title: const Text("Advance Trip"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdvanceBookingScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.redAccent),
            title: const Text("Notifications"),
            onTap: () {
              _navigateIfRequest(
                "Notifications",
                NotificationsScreen(requestId: _latestRequestId!),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help, color: Colors.redAccent),
            title: const Text("Help"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
