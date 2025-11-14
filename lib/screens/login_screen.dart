// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import 'PatientDashboard.dart';
import 'driver_dashboard.dart';
import 'admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool isLogin = true;
  String? _selectedRole;
  bool isLoading = false;

  // ---------------- LOGIN / SIGNUP FUNCTION ----------------
  Future<void> _handleAuth() async {
    if (!isLogin && _selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select your role")),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      UserCredential? userCred;

      if (isLogin) {
        userCred = await _authService.signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        userCred = await _authService.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          name: _nameController.text.trim(),
          role: _selectedRole ?? 'patient',
        );
      }

      if (userCred != null) {
        await _redirectUser(userCred.user!.uid);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ---------------- GOOGLE SIGN-IN ----------------
  Future<void> _handleGoogleSignIn() async {
    setState(() => isLoading = true);
    try {
      final userCred = await _authService.signInWithGoogle();

      if (userCred != null) {
        final uid = userCred.user!.uid;
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();

        // If first-time Google login → ask for role & name
        if (!userDoc.exists) {
          await _showRoleDialog(uid, userCred.user!.displayName ?? "User");
        }

        await _redirectUser(uid);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google Sign-In failed: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ---------------- ASK ROLE FOR GOOGLE USERS ----------------
  Future<void> _showRoleDialog(String uid, String name) async {
    String? role;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Select Role"),
        content: DropdownButtonFormField<String>(
          value: role,
          items: const [
            DropdownMenuItem(value: 'patient', child: Text('Patient')),
            DropdownMenuItem(value: 'driver', child: Text('Driver')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
          ],
          onChanged: (val) => role = val,
          decoration: const InputDecoration(
            labelText: 'Choose your role',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (role != null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .set({
                  'name': name,
                  'email': _emailController.text,
                  'role': role,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              }
            },
            child: const Text("Continue"),
          )
        ],
      ),
    );
  }

  // ---------------- ROLE-BASED REDIRECTION ----------------
  Future<void> _redirectUser(String uid) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (!userDoc.exists) {
      throw Exception("User record not found in Firestore.");
    }

    final role = userDoc['role'];
    final name = userDoc['name'] ?? "Patient"; // Correct patientName
    Widget nextScreen;

    switch (role) {
      case 'driver':
        // Dynamically fetch ambulance for this driver
        String ambulanceId = '';

        // Try to find ambulance assigned to this driver by UID
        final ambulanceQuery = await FirebaseFirestore.instance
            .collection('ambulances')
            .where('assigned_driver_uid', isEqualTo: uid)
            .get();

        if (ambulanceQuery.docs.isNotEmpty) {
          ambulanceId = ambulanceQuery.docs.first.id;
        } else {
          // Fallback: get the first available ambulance
          final allAmbulances = await FirebaseFirestore.instance
              .collection('ambulances')
              .limit(1)
              .get();

          if (allAmbulances.docs.isNotEmpty) {
            ambulanceId = allAmbulances.docs.first.id;
          }
        }

        nextScreen = DriverDashboard(
          driverName: name,
          ambulanceId: ambulanceId.isNotEmpty ? ambulanceId : 'unassigned',
        );
        break;

      case 'admin':
        nextScreen = const AdminDashboard();
        break;

      default:
        nextScreen = PatientDashboard(
          patientName: name,
        );
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => nextScreen),
      );
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_hospital,
                        color: Colors.blueAccent, size: 70),
                    const SizedBox(height: 10),
                    Text(
                      isLogin ? 'Welcome Back' : 'Create Account',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 25),
                    if (!isLogin)
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    if (!isLogin) const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!isLogin)
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        items: const [
                          DropdownMenuItem(
                              value: 'patient', child: Text('Patient')),
                          DropdownMenuItem(
                              value: 'driver', child: Text('Driver')),
                          DropdownMenuItem(
                              value: 'admin', child: Text('Admin')),
                        ],
                        onChanged: (val) => setState(() => _selectedRole = val),
                        decoration: const InputDecoration(
                          labelText: 'Select Role',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isLoading ? null : _handleAuth,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 90, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        isLoading
                            ? 'Please wait...'
                            : isLogin
                                ? 'Login'
                                : 'Sign Up',
                        style:
                            const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Expanded(child: Divider(thickness: 1)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text("or continue with"),
                        ),
                        Expanded(child: Divider(thickness: 1)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: isLoading ? null : _handleGoogleSignIn,
                      icon: Image.asset('assets/image.png', height: 22),
                      label: const Text("Sign in with Google"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? "Don't have an account? Sign Up"
                            : "Already have an account? Login",
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
