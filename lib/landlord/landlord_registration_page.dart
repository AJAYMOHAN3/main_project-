import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:main_project/main.dart';

class LandlordRegistrationPage extends StatefulWidget {
  const LandlordRegistrationPage({super.key});

  @override
  LandlordRegistrationPageState createState() =>
      LandlordRegistrationPageState();
}

class LandlordRegistrationPageState extends State<LandlordRegistrationPage> {
  String? _gender;
  final List<String> genders = ['Male', 'Female', 'Other'];

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _registerLandlord() async {
    if (_isLoading) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final String fullName = _fullNameController.text.trim();
    final String email = _emailController.text.trim();
    final String phoneNumber = _phoneController.text.trim();
    final String password = _passwordController.text;
    final String? gender = _gender;

    String? validationError;

    if (email.isEmpty ||
        password.isEmpty ||
        fullName.isEmpty ||
        phoneNumber.isEmpty ||
        gender == null) {
      validationError = 'Please fill all required fields.';
    } else if (!EmailValidator.validate(email)) {
      validationError = 'Please enter a valid email address.';
    } else if (!RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
      validationError = 'Phone number must be exactly 10 digits.';
    } else if (password.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      validationError =
          'Password must be at least 8 characters long and contain 1 uppercase, 1 lowercase, and 1 special character.';
    }

    // --- If basic validation fails, show error Snackbar and exit ---
    if (validationError != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Registering... Please wait.')),
    );

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      String uid = userCredential.user!.uid;

      await FirebaseFirestore.instance.collection('landlord').doc(uid).set({
        'uid': uid,
        'fullName': fullName,
        'email': email,
        'phoneNumber': phoneNumber,
        'gender': gender,
        'role': 1,
      });

      await FirebaseFirestore.instance.collection('email').add({
        'email': email,
      });

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Registration Successful!'), // Plain text
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        //print("--- _registerLandlord: Navigating back... ---");
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        // print("--- _registerLandlord: NOT navigating (unmounted) ---");
      }
    } catch (e) {
      // print("--- _registerLandlord: *** CATCH BLOCK ENTERED *** ---");
      //print("--- _registerLandlord: Error: $e ---");
      // Hide 'Registering...' (Safely attempt)
      try {
        scaffoldMessenger.hideCurrentSnackBar();
      } catch (_) {}

      // Determine error message
      String errorMessage =
          'Registration failed. Please try again.'; // Plain text default
      if (e is FirebaseAuthException) {
        errorMessage =
            'Registration failed: ${e.message ?? e.code}'; // Plain text Firebase error
      } else if (e is Exception) {
        // Display validation or profile name taken messages directly
        errorMessage = e.toString().replaceFirst(
          'Exception: ',
          '',
        ); // Remove "Exception: " prefix, plain text
      } else {
        errorMessage =
            'Registration failed: ${e.toString()}'; // Plain text other error
      }
      //print(
      //"--- _registerLandlord: Error message determined: $errorMessage ---",
      ////);

      // Show error Snackbar
      //print("--- _registerLandlord: Showing ERROR Snackbar ---");
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage), // Plain text
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      // print("--- _registerLandlord: Entering FINALLY block ---");
      // Ensure loading state is reset ONLY if the widget is still mounted
      if (mounted) {
        // print("--- _registerLandlord: Setting isLoading = false ---");
        setState(() {
          _isLoading = false;
          // print(
          // "--- _registerLandlord: setState (isLoading=false) completed ---",
          //);
        });
      } else {
        // print("--- _registerLandlord: NOT setting isLoading (unmounted) ---");
      }
      //print("--- _registerLandlord: Exiting FINALLY block ---");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
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
          SafeArea(
            child: Column(
              children: [
                const CustomTopNavBar(showBack: true, title: ''),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(25.0),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(24.0),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(25.0),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "Landlord Registration",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // --- ASSIGN CONTROLLERS ---
                                CustomTextField(
                                  hintText: 'Full Name',
                                  controller: _fullNameController,
                                ),
                                const SizedBox(height: 16),
                                CustomTextField(
                                  hintText: 'Email',
                                  controller: _emailController,
                                ),
                                const SizedBox(height: 16),
                                CustomTextField(
                                  hintText: 'Phone Number',
                                  controller: _phoneController,
                                ),
                                const SizedBox(height: 16),
                                CustomTextField(
                                  hintText: 'Password',
                                  obscureText: true,
                                  controller: _passwordController,
                                ),
                                const SizedBox(height: 16),
                                DropdownContainer(
                                  label: "Gender",
                                  value: _gender,
                                  items: genders,
                                  onChanged: (val) {
                                    setState(() {
                                      _gender = val;
                                    });
                                  },
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: _isLoading
                                      ? null // Disable button while loading
                                      : _registerLandlord,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    backgroundColor: Colors.orange.shade700,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    disabledBackgroundColor:
                                        Colors.grey.shade600,
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
