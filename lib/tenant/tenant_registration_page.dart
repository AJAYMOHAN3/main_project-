import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:main_project/main.dart';

class TenantRegistrationPage extends StatefulWidget {
  const TenantRegistrationPage({super.key});

  @override
  TenantRegistrationPageState createState() => TenantRegistrationPageState();
}

class TenantRegistrationPageState extends State<TenantRegistrationPage> {
  String? _gender;
  final List<String> genders = ['Male', 'Female', 'Other'];
  final _fullNameController = TextEditingController();
  final _profileNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _preferredLocationController =
      TextEditingController(); // Renamed for clarity
  bool _isLoading = false;

  // --- DISPOSE ---
  @override
  void dispose() {
    _fullNameController.dispose();
    _profileNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _preferredLocationController.dispose();
    super.dispose();
  }

  // --- ADD TENANT REGISTRATION FUNCTION ---
  Future<void> _registerTenant() async {
    // Prevent multiple submissions if already loading
    if (_isLoading) return;

    // Use a local variable for ScaffoldMessenger
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // --- Get values first for validation ---
    final String fullName = _fullNameController.text.trim();
    final String profileName = _profileNameController.text
        .trim(); // Trim for check and storage
    final String email = _emailController.text.trim();
    final String phoneNumber = _phoneController.text.trim();
    final String password =
        _passwordController.text; // No trim for password validation
    final String preferredLocation = _preferredLocationController.text.trim();
    final String? gender = _gender;

    // --- START VALIDATION (Before setting loading state) ---
    String? validationError;

    // 1. Check for empty fields first
    if (email.isEmpty ||
        password.isEmpty || // Check non-trimmed password for empty
        fullName.isEmpty ||
        profileName.isEmpty || // Check trimmed profile name
        phoneNumber.isEmpty ||
        preferredLocation.isEmpty ||
        gender == null) {
      validationError = 'Please fill all required fields'; // Plain text
    }
    // 2. Validate Email Format (assuming EmailValidator is imported elsewhere)
    else if (!EmailValidator.validate(email)) {
      validationError = 'Please enter a valid email address'; // Plain text
    }
    // 3. Validate Phone Number (exactly 10 digits)
    else if (!RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
      validationError = 'Phone number must be exactly 10 digits'; // Plain text
    }
    // 4. Validate Password Length
    else if (password.length < 6) {
      validationError =
          'Password must be at least 6 characters long'; // Plain text
    }
    // 5. Validate Password Format (Alphanumeric only)
    else if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(password)) {
      validationError =
          'Password must contain only letters and numbers'; // Plain text
    }

    // --- If validation fails, show error Snackbar and exit ---
    if (validationError != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(validationError), // Plain text
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return; // Stop the registration process here
    }
    // --- END BASIC VALIDATION ---

    // --- Set loading state ONLY after basic validation passes ---
    setState(() {
      _isLoading = true;
    });

    // Show 'Registering...' Snackbar AFTER validation passes
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Registering Please wait'), // Plain text
        // duration removed, will hide manually
      ),
    );

    try {
      // --- CHECK PROFILE NAME UNIQUENESS ---
      final querySnapshot = await FirebaseFirestore.instance
          .collection('UserIds')
          .where(
            'UserId',
            isEqualTo: profileName,
          ) // Check against the trimmed profileName
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // If docs list is not empty, the profile name is taken
        throw Exception(
          'Profile name already taken Please choose another',
        ); // Plain text
      }
      // --- END PROFILE NAME UNIQUENESS CHECK ---

      // 1. Register with Firebase Auth (Only proceeds if profile name is unique)
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email, // Use trimmed email
            password: password, // Use non-trimmed password
          );

      String uid = userCredential.user!.uid;

      // 2. Store data in Firestore under 'tenant' collection
      await FirebaseFirestore.instance.collection('tenant').doc(uid).set({
        'uid': uid,
        'fullName': fullName, // Use trimmed value
        'profileName': profileName, // Use trimmed value
        'email': email, // Use trimmed value
        'phoneNumber': phoneNumber, // Use trimmed value
        'preferredLocation': preferredLocation, // Use trimmed value
        'gender': gender,
        'role': 0, // Store role = 0 for Tenant
      });

      // 3. Store unique profile name in UserIds collection (AFTER tenant data is saved)
      await FirebaseFirestore.instance.collection('UserIds').add({
        'UserId': profileName, // Store the unique, trimmed profile name
      });

      // --- Hide 'Registering...' and Show Success ---
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Registration Successful'), // Plain text
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Wait a moment for user to see the success message before navigating
      await Future.delayed(const Duration(milliseconds: 1500));

      // Original Navigation on Success (Check if still mounted)
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      // Hide 'Registering...' (Safely attempt)
      try {
        scaffoldMessenger.hideCurrentSnackBar();
      } catch (_) {}

      // Determine error message (Firebase Auth errors take priority)
      String errorMessage =
          'Registration failed Please try again'; // Plain text
      if (e is FirebaseAuthException) {
        // Use plain text for Firebase errors too
        errorMessage = 'Registration failed ${e.message ?? e.code}';
      } else if (e is Exception) {
        // Display validation or profile name taken messages directly (plain text)
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      } else {
        // Display any other exception message plainly
        errorMessage = 'Registration failed ${e.toString()}';
      }

      // Show error Snackbar
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage), // Plain text
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      // Ensure loading state is reset ONLY if the widget is still mounted
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- NO CHANGES TO THE UI STRUCTURE BELOW ---
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
                                  "Tenant Registration",
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
                                  hintText: 'Preferred Location',
                                  controller:
                                      _preferredLocationController, // Use correct controller
                                ),
                                // --- END ASSIGN CONTROLLERS ---
                                const SizedBox(height: 16),
                                DropdownContainer(
                                  label: 'Gender',
                                  value: _gender,
                                  items: genders, // Use the defined list
                                  onChanged: (val) {
                                    setState(() {
                                      _gender = val;
                                    });
                                  },
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  // --- CHANGE ONPRESSED TO CALL REGISTER FUNCTION ---
                                  onPressed: _isLoading
                                      ? null
                                      : _registerTenant,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    backgroundColor: Colors.orange.shade700,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    // Dim button when loading
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
