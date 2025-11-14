import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;

  final List<String> _tabs = [
    'Dashboard',
    'Manage Users',
    'Manage Requests',
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildDashboard(),
      _buildUsers(),
      _buildRequests(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_currentIndex]),
        backgroundColor: Colors.redAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.redAccent,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Users"),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_hospital), label: "Requests"),
        ],
      ),
    );
  }

  // ----------------- DASHBOARD -----------------
  Widget _buildDashboard() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, userSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('requests').snapshots(),
          builder: (context, requestSnapshot) {
            if (!userSnapshot.hasData || !requestSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final users = userSnapshot.data!.docs;
            final requests = requestSnapshot.data!.docs;

            final patients = users.where((u) => u['role'] == 'patient').length;
            final drivers = users.where((u) => u['role'] == 'driver').length;
            final totalRequests = requests.length;
            final completed =
                requests.where((r) => r['status'] == 'completed').length;
            final pending =
                requests.where((r) => r['status'] == 'pending').length;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildStatCard("Patients", patients, Colors.blue),
                  _buildStatCard("Drivers", drivers, Colors.green),
                  _buildStatCard(
                      "Total Requests", totalRequests, Colors.orange),
                  _buildStatCard("Completed", completed, Colors.purple),
                  _buildStatCard("Pending", pending, Colors.red),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: [
              color.withAlpha((0.8 * 255).toInt()), // 0.8 opacity
              color.withAlpha((0.4 * 255).toInt()), // 0.4 opacity
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: const TextStyle(
                  fontSize: 30,
                  color: Colors.white,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------- USERS TAB -----------------
  Widget _buildUsers() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!.docs;

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final data = users[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: Icon(
                  data['role'] == 'driver' ? Icons.local_taxi : Icons.person,
                  color: data['role'] == 'driver' ? Colors.green : Colors.blue,
                ),
                title: Text(data['name'] ?? 'Unknown'),
                subtitle: Text("${data['email']}\nRole: ${data['role']}"),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(users[index].id)
                        .delete();
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ----------------- REQUESTS TAB -----------------
  Widget _buildRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final requests = snapshot.data!.docs;

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final data = requests[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: Icon(
                  Icons.emergency,
                  color: data['status'] == 'completed'
                      ? Colors.green
                      : Colors.orange,
                ),
                title: Text(data['name'] ?? 'Unknown Patient'),
                subtitle: Text(
                    "Status: ${data['status']}\nLocation: ${data['location']?['lat']}, ${data['location']?['lng']}"),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('requests')
                        .doc(requests[index].id)
                        .delete();
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ----------------- DRAWER -----------------
  Drawer _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.redAccent),
            child: Center(
              child: Text("Admin Menu",
                  style: TextStyle(color: Colors.white, fontSize: 22)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text("Dashboard"),
            onTap: () => setState(() => _currentIndex = 0),
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text("Manage Users"),
            onTap: () => setState(() => _currentIndex = 1),
          ),
          ListTile(
            leading: const Icon(Icons.local_hospital),
            title: const Text("Manage Requests"),
            onTap: () => setState(() => _currentIndex = 2),
          ),
        ],
      ),
    );
  }
}
