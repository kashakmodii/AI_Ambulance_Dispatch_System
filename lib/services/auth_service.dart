import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // ---------------- GOOGLE SIGN-IN ----------------
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn(
        clientId:
            '305192039236-ef5ssjlhqea5ismog2jcmugrdknbjo3j.apps.googleusercontent.com',
      ).signIn();

      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await _auth.signInWithCredential(credential);
      final user = userCred.user!;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': user.displayName,
          'email': user.email,
          'role': 'select_role',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return userCred;
    } catch (e) {
      print("Google Sign-In Error: $e");
      return null;
    }
  }

  // ---------------- EMAIL SIGNUP ----------------
  Future<UserCredential?> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    try {
      final userCred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCred.user!;
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name,
        'email': email,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return userCred;
    } catch (e) {
      print("Signup Error: $e");
      return null;
    }
  }

  // ---------------- EMAIL LOGIN ----------------
  Future<UserCredential?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final userCred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCred;
    } catch (e) {
      print("Login Error: $e");
      return null;
    }
  }

  // ---------------- LOGOUT ----------------
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  Stream<User?> get userChanges => _auth.authStateChanges();
}
