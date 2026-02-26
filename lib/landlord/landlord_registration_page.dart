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
  String? _houseType;
  final List<String> genders = ['Male', 'Female', 'Other'];
  final List<String> houseTypes = ['Apartment', 'Villa', 'Studio', 'Duplex'];

  final _fullNameController = TextEditingController();
  final _profileNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _houseLocationController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _profileNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _houseLocationController.dispose();
    super.dispose();
  }

  Future<void> _registerLandlord() async {
    if (_isLoading) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final String fullName = _fullNameController.text.trim();
    final String profileName = _profileNameController.text.trim();
    final String email = _emailController.text.trim();
    final String phoneNumber = _phoneController.text.trim();
    final String password = _passwordController.text;
    final String houseLocation = _houseLocationController.text.trim();
    final String? gender = _gender;
    final String? houseType = _houseType;

    String? validationError;

    if (email.isEmpty ||
        password.isEmpty ||
        fullName.isEmpty ||
        profileName.isEmpty ||
        phoneNumber.isEmpty ||
        houseLocation.isEmpty ||
        gender == null ||
        houseType == null) {
      validationError = 'Please fill all required fields.';
    } else if (!EmailValidator.validate(email)) {
      validationError = 'Please enter a valid email address.';
    } else if (!RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
      validationError = 'Phone number must be exactly 10 digits.';
    } else if (password.length < 6) {
      validationError = 'Password must be at least 6 characters long.';
    } else if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(password)) {
      validationError =
          'Password must contain only letters and numbers (no symbols or spaces).';
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
      final querySnapshot = await FirebaseFirestore.instance
          .collection('UserIds')
          .where('UserId', isEqualTo: profileName)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        throw Exception('Profile name already taken. Please choose another.');
      }
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      String uid = userCredential.user!.uid;

      await FirebaseFirestore.instance.collection('landlord').doc(uid).set({
        'uid': uid,
        'fullName': fullName,
        'profileName': profileName, // Store trimmed profile name
        'email': email,
        'phoneNumber': phoneNumber,
        'houseLocation': houseLocation,
        'gender': gender,
        'houseType': houseType,
        'role': 1,
      });

      await FirebaseFirestore.instance.collection('UserIds').add({
        'UserId': profileName,
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
                                  hintText: 'Profile Name',
                                  controller: _profileNameController,
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
                                CustomTextField(
                                  hintText: 'House Location',
                                  controller: _houseLocationController,
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
                                const SizedBox(height: 16),
                                DropdownContainer(
                                  label: "House Type",
                                  value: _houseType,
                                  items: houseTypes,
                                  onChanged: (val) {
                                    setState(() {
                                      _houseType = val;
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
