import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF141E30), Color(0xFF243B55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        const InfiniteDAGBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const CustomTopNavBar(title: ''),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 60.0,
                      horizontal: 16.0,
                    ),
                    child: const GlassmorphismCard(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class GlassmorphismCard extends StatefulWidget {
  const GlassmorphismCard({super.key});

  @override
  State<GlassmorphismCard> createState() => _GlassmorphismCardState();
}

class _GlassmorphismCardState extends State<GlassmorphismCard> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSendingResetEmail = false;

  // Helper to check platform
  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Helper to parse Firestore integer from REST JSON
  int? _parseIntFromFirestore(dynamic val) {
    if (val == null) return null;
    if (val is Map) {
      if (val.containsKey('integerValue')) {
        return int.tryParse(val['integerValue'].toString());
      }
    }
    return null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Logging in Please wait'),
        duration: Duration(minutes: 1),
      ),
    );

    try {
      String localUid = '';
      int? userRole;

      if (useNativeSdk) {
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);

        localUid = userCredential.user!.uid;

        DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
            .collection('landlord')
            .doc(localUid)
            .get();

        if (landlordDoc.exists) {
          var data = landlordDoc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('role') && data['role'] is int) {
            userRole = data['role'] as int?;
          }
        } else {
          DocumentSnapshot tenantDoc = await FirebaseFirestore.instance
              .collection('tenant')
              .doc(localUid)
              .get();
          if (tenantDoc.exists) {
            var data = tenantDoc.data() as Map<String, dynamic>?;
            if (data != null &&
                data.containsKey('role') &&
                data['role'] is int) {
              userRole = data['role'] as int?;
            }
          }
        }
      } else {
        final authUrl = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$kFirebaseAPIKey',
        );

        final authResponse = await http.post(
          authUrl,
          body: jsonEncode({
            "email": email,
            "password": password,
            "returnSecureToken": true,
          }),
          headers: {"Content-Type": "application/json"},
        );

        if (authResponse.statusCode != 200) {
          throw FirebaseAuthException(
            code: 'invalid-credential',
            message: 'Invalid Login',
          );
        }

        final authData = jsonDecode(authResponse.body);
        localUid = authData['localId'];

        // Check Landlord via REST
        final lUrl = Uri.parse(
          '$kFirestoreBaseUrl/landlord/$localUid?key=$kFirebaseAPIKey',
        );
        final lResp = await http.get(lUrl);

        if (lResp.statusCode == 200) {
          final lData = jsonDecode(lResp.body);
          if (lData['fields'] != null && lData['fields']['role'] != null) {
            userRole = _parseIntFromFirestore(lData['fields']['role']);
          }
        } else {
          // Check Tenant via REST
          final tUrl = Uri.parse(
            '$kFirestoreBaseUrl/tenant/$localUid?key=$kFirebaseAPIKey',
          );
          final tResp = await http.get(tUrl);

          if (tResp.statusCode == 200) {
            final tData = jsonDecode(tResp.body);
            if (tData['fields'] != null && tData['fields']['role'] != null) {
              userRole = _parseIntFromFirestore(tData['fields']['role']);
            }
          }
        }
      }

      scaffoldMessenger.hideCurrentSnackBar();

      if (userRole == 1) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', localUid);
        await prefs.setInt('user_role', 1);

        role = 1;
        uid = localUid;

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LandlordHomePage()),
          );
        }
      } else if (userRole == 0) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', localUid);
        await prefs.setInt('user_role', 0);

        role = 0;
        uid = localUid;

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const TenantHomePage()),
          );
        }
      } else {
        throw Exception('User role not found or invalid');
      }
    } catch (e) {
      try {
        scaffoldMessenger.hideCurrentSnackBar();
      } catch (_) {}

      String errorMessage = 'Invalid username or password';
      if (e is FirebaseAuthException) {
        errorMessage = 'Invalid username or password';
      } else {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    if (_isSendingResetEmail || _isLoading) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final String email = _emailController.text.trim();

    if (email.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address first'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    if (!EmailValidator.validate(email)) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _isSendingResetEmail = true;
    });

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Sending password reset email.'),
        duration: Duration(minutes: 1),
      ),
    );

    try {
      if (useNativeSdk) {
        // --- SDK LOGIC (Android/iOS) ---
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      } else {
        // --- REST LOGIC (Web/Windows/Linux/MacOS) ---
        final url = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$kFirebaseAPIKey',
        );
        final response = await http.post(
          url,
          body: jsonEncode({"requestType": "PASSWORD_RESET", "email": email}),
          headers: {"Content-Type": "application/json"},
        );

        if (response.statusCode != 200) {
          throw Exception("Failed to send reset email");
        }
      }

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      try {
        scaffoldMessenger.hideCurrentSnackBar();
      } catch (_) {}

      String errorMessage = 'Failed to send reset email.';
      if (e is FirebaseAuthException) {
        errorMessage = 'Failed to send reset email ${e.message ?? e.code}';
      } else {
        errorMessage = 'Failed to send reset email ${e.toString()}';
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingResetEmail = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: Container(
          padding: const EdgeInsets.all(30.0),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(25.0),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTextField(hintText: 'Email', controller: _emailController),
              const SizedBox(height: 25),
              CustomTextField(
                hintText: 'Password',
                obscureText: true,
                controller: _passwordController,
              ),
              const SizedBox(height: 35),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.orange.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.grey.shade600,
                      ),
                      child: const Text(
                        'LOGIN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) =>
                              const RoleSelectionDialog(),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'REGISTER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              TextButton(
                onPressed: _isSendingResetEmail ? null : _forgotPassword,
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: _isSendingResetEmail
                        ? Colors.grey
                        : Colors.white.withValues(alpha: 0.7),
                    decoration: TextDecoration.underline,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
