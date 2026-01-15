import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'package:email_validator/email_validator.dart';
import 'package:image_picker/image_picker.dart';

import 'landlord.dart';
import 'tenant.dart';

int? role;
String? uid;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --- CHECK PERSISTENT LOGIN ---
  Widget startScreen = const LoginPage(); // Default to login page

  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? storedUid = prefs.getString('user_id');
    final int? storedRole = prefs.getInt('user_role');

    if (storedUid != null && storedRole != null) {
      // Restore session variables
      uid = storedUid;
      role = storedRole;

      // Determine start screen based on role
      if (storedRole == 1) {
        startScreen = const LandlordHomePage();
      } else if (storedRole == 0) {
        startScreen = const TenantHomePage();
      }
    }
  } catch (e) {
    //print("Error checking login status: $e");
    // Fallback to LoginPage on error
  }
  // -------------------------------

  runApp(MyApp(startScreen: startScreen));
}

// -------------------- APP ENTRY --------------------

class MyApp extends StatelessWidget {
  final Widget startScreen; // Add this variable

  // Update constructor to accept startScreen
  const MyApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secure Homes',
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
      // Use the determined startScreen instead of hardcoded LoginPage
      home: startScreen,
    );
  }
}

// -------------------- LOGIN PAGE --------------------

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

// -------------------- GLASS CARD LOGIN --------------------

class GlassmorphismCard extends StatefulWidget {
  const GlassmorphismCard({super.key});

  @override
  State<GlassmorphismCard> createState() => _GlassmorphismCardState();
}

class _GlassmorphismCardState extends State<GlassmorphismCard> {
  // --- ADD CONTROLLERS AND LOADING STATE ---
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  // --- ADD isLoading FOR FORGOT PASSWORD ---
  bool _isSendingResetEmail = false;

  // --- ADD DISPOSE METHOD ---
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Prevent multiple clicks if already loading
    if (_isLoading) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final String email = _emailController.text.trim();
    final String password = _passwordController.text; // Don't trim password

    // --- VALIDATION FIRST ---
    if (email.isEmpty || password.isEmpty) {
      // Show the specific error immediately and exit
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter email and password',
          ), // Plain text error for empty fields
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return; // Stop the function here before showing "Logging in..."
    }
    // --- END VALIDATION ---

    // --- Set loading state ONLY if validation passed ---
    setState(() {
      _isLoading = true;
    });

    // Show loading indicator now that fields are not empty
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Logging in Please wait'),
        duration: Duration(minutes: 1),
      ),
    );

    try {
      // 1. Sign in with Firebase Auth (Email/Password are known not to be empty here)
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      // --- Renamed local variable to avoid conflict with global 'uid' ---
      String localUid = userCredential.user!.uid;

      // 2. Check Firestore for role
      DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(localUid) // --- Use localUid ---
          .get();

      int? userRole; // Variable to store the role found

      if (landlordDoc.exists) {
        // Try casting safely
        var data = landlordDoc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('role') && data['role'] is int) {
          userRole = data['role'] as int?;
        }
      } else {
        // If not found in landlord, check tenant
        DocumentSnapshot tenantDoc = await FirebaseFirestore.instance
            .collection('tenant')
            .doc(localUid) // --- Use localUid ---
            .get();
        if (tenantDoc.exists) {
          var data = tenantDoc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('role') && data['role'] is int) {
            userRole = data['role'] as int?;
          }
        }
      }

      // --- Hide loading Snackbar ---
      scaffoldMessenger.hideCurrentSnackBar();

      // 3. Navigate based on role
      if (userRole == 1) {
        // --- ADDED: SAVE TO SHARED PREFERENCES AND GLOBAL VARIABLE ---
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', localUid); // Save localUid to prefs
        await prefs.setInt('user_role', 1); // Save role to prefs

        // --- ASSIGN TO GLOBAL VARIABLES ---
        role = 1; // Update global role variable
        uid = localUid; // Update global uid variable
        // --- END ASSIGN ---

        // Navigate to LandlordHomePage
        if (mounted) {
          Navigator.pushReplacement(
            // Use pushReplacement to prevent back button to login
            context,
            MaterialPageRoute(builder: (context) => const LandlordHomePage()),
          );
        }
      } else if (userRole == 0) {
        // --- ADDED: SAVE TO SHARED PREFERENCES AND GLOBAL VARIABLE ---
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', localUid); // Save localUid to prefs
        await prefs.setInt('user_role', 0); // Save role to prefs

        // --- ASSIGN TO GLOBAL VARIABLES ---
        role = 0; // Update global role variable
        uid = localUid; // Update global uid variable
        // --- END ASSIGN ---

        // Navigate to TenantHomePage
        if (mounted) {
          Navigator.pushReplacement(
            // Use pushReplacement
            context,
            MaterialPageRoute(builder: (context) => const TenantHomePage()),
          );
        }
      } else {
        // Role not found or invalid
        throw Exception('User role not found or invalid');
      }
    } catch (e) {
      // --- Hide loading Snackbar ---
      try {
        scaffoldMessenger.hideCurrentSnackBar();
      } catch (_) {}

      // Show error Snackbar
      String errorMessage = 'Invalid username or password'; // Default message
      if (e is FirebaseAuthException) {
        // Keep the generic message for Auth errors as requested
        errorMessage = 'Invalid username or password';
      } else {
        // Show other errors (like role not found) plainly
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage), // Plain text
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
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

  Future<void> _forgotPassword() async {
    if (_isSendingResetEmail || _isLoading) {
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final String email = _emailController.text.trim();

    // Basic email validation
    if (email.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address first'), // Plain text
          backgroundColor: Colors.orange, // Use orange for warning
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    // Basic email format check (optional but good)
    if (!EmailValidator.validate(email)) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'), // Plain text
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _isSendingResetEmail = true;
    }); // Set loading specific to this action

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Sending password reset email.'),
        duration: Duration(minutes: 1),
      ), // Plain text
    );

    try {
      // Send password reset email using Firebase Auth
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      // --- Success ---
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent.'), // Plain text
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5), // Show longer
        ),
      );
    } catch (e) {
      // --- Failure ---
      try {
        scaffoldMessenger.hideCurrentSnackBar();
      } catch (_) {}

      String errorMessage = 'Failed to send reset email.'; // Plain text default
      if (e is FirebaseAuthException) {
        // Provide specific Firebase error messages if possible (plainly)
        errorMessage = 'Failed to send reset email ${e.message ?? e.code}';
      } else {
        errorMessage =
            'Failed to send reset email ${e.toString()}'; // Plain text other error
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage), // Plain text
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      // Reset loading state for this specific action
      if (mounted) {
        setState(() {
          _isSendingResetEmail = false;
        });
      }
    }
  }
  // --- END FORGOT PASSWORD FUNCTION ---

  @override
  Widget build(BuildContext context) {
    // --- NO UI CHANGES BELOW ---
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
              // --- ASSIGN CONTROLLERS ---
              CustomTextField(
                hintText: 'Email', // Assuming this is Email
                controller: _emailController,
              ),
              const SizedBox(height: 25),
              CustomTextField(
                hintText: 'Password',
                obscureText: true,
                controller: _passwordController,
              ),
              // --- END ASSIGN CONTROLLERS ---
              const SizedBox(height: 35),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      // --- UPDATE ONPRESSED ---
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.orange.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        // Dim button when loading
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
                        // Original Register button action remains
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
                // --- UPDATE ONPRESSED FOR FORGOT PASSWORD ---
                onPressed: _isSendingResetEmail
                    ? null
                    : _forgotPassword, // Disable while sending
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    // Dim text slightly if disabled
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
} // End of _GlassmorphismCardState

class CustomTopNavBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBack;
  final String title;
  final VoidCallback? onBack; // Custom back handler

  const CustomTopNavBar({
    super.key,
    this.showBack = false,
    required this.title,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3)),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ---------- LEFT SIDE: Back Button + Branding ----------
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Back Button (Conditional)
                if (showBack)
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: 24,
                    ),
                    padding:
                        EdgeInsets.zero, // Remove extra padding for a tight fit
                    constraints: const BoxConstraints(), // Allow minimal space
                    onPressed: () {
                      // CRITICAL FIX: Use the custom onBack logic
                      if (onBack != null) {
                        onBack!(); // Uses the tab history logic from LandlordHomePage
                      } else if (Navigator.canPop(context)) {
                        Navigator.pop(context); // Fallback for standard routes
                      }
                    },
                  )
                else
                  // If no back button, show a placeholder for logo/name to start immediately
                  const SizedBox.shrink(),

                // 2. Logo/Icon
                const SizedBox(width: 8), // Small space after back button
                // NOTE: Using a placeholder icon as the asset path is local
                Image.asset(
                  'lib/assets/icon.png',
                  height: 32,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback icon if asset path is not working
                    return const Icon(
                      Icons.security,
                      color: Colors.white,
                      size: 32,
                    );
                  },
                ),

                // 3. App Name
                const SizedBox(width: 12),
                const Text(
                  'SECURE HOMES', // App Name
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),

            // ---------- RIGHT SIDE: Spacer (Empty/Optional Action Button) ----------
            const SizedBox.shrink(), // Keeps the mainAxisAlignment: spaceBetween correct
          ],
        ),
      ),
    );
  }
}

// -------------------- ROLE SELECTION DIALOG --------------------

class RoleSelectionDialog extends StatelessWidget {
  const RoleSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Your Role',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const TenantRegistrationPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.teal.withValues(alpha: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Register as Tenant',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const LandlordRegistrationPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.indigo.withValues(alpha: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Register as Landlord',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- TENANT REGISTRATION --------------------
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

// -------------------- LANDLORD REGISTRATION --------------------

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

    // --- Get values first for validation ---
    final String fullName = _fullNameController.text.trim();
    final String profileName = _profileNameController.text
        .trim(); // Trim profile name for check and storage
    final String email = _emailController.text.trim();
    final String phoneNumber = _phoneController.text.trim();
    final String password = _passwordController.text; // No trim for password
    final String houseLocation = _houseLocationController.text.trim();
    final String? gender = _gender;
    final String? houseType = _houseType;

    // --- START VALIDATION ---
    String? validationError;

    if (email.isEmpty ||
        password.isEmpty ||
        fullName.isEmpty ||
        profileName.isEmpty || // Check trimmed profile name
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
      return; // Stop the registration process here
    }
    // --- END BASIC VALIDATION ---

    // --- Set loading state ONLY after basic validation passes ---
    setState(() {
      _isLoading = true;
    });

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Registering... Please wait.')),
    );

    try {
      // --- CHECK PROFILE NAME UNIQUENESS ---
      // print("--- Checking profile name uniqueness for: $profileName ---");
      final querySnapshot = await FirebaseFirestore.instance
          .collection('UserIds')
          .where(
            'UserId',
            isEqualTo: profileName,
          ) // Check against the trimmed profileName
          .limit(1) // We only need to know if at least one exists
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // print("--- Profile name '$profileName' already exists. ---");
        // If docs list is not empty, the profile name is taken
        throw Exception('Profile name already taken. Please choose another.');
      }
      //print("--- Profile name '$profileName' is unique. Proceeding... ---");
      // --- END PROFILE NAME UNIQUENESS CHECK ---

      // 1. Register with Firebase Auth (Only proceeds if profile name is unique)
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      String uid = userCredential.user!.uid;
      //print("--- FirebaseAuth SUCCEEDED - UID: $uid ---");

      // 2. Store landlord data in Firestore
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
      //print("--- Firestore set (landlord collection) SUCCEEDED ---");

      // 3. Store unique profile name in UserIds collection (AFTER landlord data is saved)
      await FirebaseFirestore.instance.collection('UserIds').add({
        'UserId': profileName, // Store the unique, trimmed profile name
      });
      //print("--- Firestore add (UserIds collection) SUCCEEDED ---");

      // --- Success ---
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
} // End of _LandlordRegistrationPageState class

// -------------------- DROPDOWN CONTAINER --------------------
class DropdownContainer extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const DropdownContainer({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          hint: Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 16),
          ),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
          style: const TextStyle(color: Colors.black87, fontSize: 16),
          dropdownColor: Colors.white.withValues(alpha: 0.95),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// -------------------- CUSTOM TEXT FIELD --------------------

// Add this import at the top of the file where DocumentField is defined

class DocumentField {
  String? selectedDoc;
  File? pickedFile; // <-- ADDED: To hold the selected file
  String? downloadUrl; // <-- ADDED: To optionally hold the URL after upload

  DocumentField({
    this.selectedDoc,
    this.pickedFile, // <-- ADDED to constructor (optional)
    this.downloadUrl, // <-- ADDED to constructor (optional)
  });
}

class PropertyCard {
  List<DocumentField> documents;
  List<XFile> houseImages = []; // <-- ADD THIS LINE TO HOLD IMAGES

  // --- Controllers remain the same ---
  // final TextEditingController houseNameController = TextEditingController(); // This was removed as requested earlier
  final TextEditingController roomTypeController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController rentController = TextEditingController();
  final TextEditingController maxOccupancyController = TextEditingController();

  PropertyCard({required this.documents});

  // --- Dispose method remains the same (removed houseNameController) ---
  void dispose() {
    // houseNameController.dispose(); // REMOVED
    roomTypeController.dispose();
    locationController.dispose();
    rentController.dispose();
    maxOccupancyController.dispose();
  }
}

// This class might need 'package:flutter/material.dart' imported in its file too
class CustomTextField extends StatelessWidget {
  final String hintText;
  final bool obscureText;
  final TextEditingController? controller;
  final TextInputType? keyboardType; // <-- 1. ADD THIS LINE

  const CustomTextField({
    super.key,
    required this.hintText,
    this.obscureText = false,
    this.controller,
    this.keyboardType, // <-- 2. ADD THIS TO THE CONSTRUCTOR
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType, // <-- 3. PASS THE KEYBOARD TYPE HERE
      style: const TextStyle(color: Colors.black87),
      cursorColor: Theme.of(context).primaryColor,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 20,
        ),
      ),
    );
  }
}

// -------------------- INFINITE DAG BACKGROUND --------------------

class InfiniteDAGBackground extends StatefulWidget {
  const InfiniteDAGBackground({super.key});

  @override
  InfiniteDAGBackgroundState createState() => InfiniteDAGBackgroundState();
}

class InfiniteDAGBackgroundState extends State<InfiniteDAGBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Offset> _nodes = [];
  List<Offset> _directions = [];
  final int nodeCount = 20;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  void _initializeNodes(Size screenSize) {
    final random = Random();
    _nodes = [];
    _directions = [];

    _nodes.add(Offset(screenSize.width / 2, 50));
    _directions.add(const Offset(0, 0));

    for (int i = 1; i < nodeCount; i++) {
      double dx =
          screenSize.width * 0.1 +
          (screenSize.width * 0.8) * random.nextDouble();
      double dy = 80 + (screenSize.height * 0.7) * random.nextDouble();
      _nodes.add(Offset(dx, dy));

      double dirX =
          (random.nextBool() ? 1 : -1) * (0.5 + random.nextDouble() * 0.5);
      double dirY =
          (random.nextBool() ? 1 : -1) * (0.5 + random.nextDouble() * 0.5);
      _directions.add(Offset(dirX, dirY));
    }

    _initialized = true;

    _controller.addListener(() {
      if (mounted) {
        setState(() {
          for (int i = 1; i < _nodes.length; i++) {
            Offset p = _nodes[i] + _directions[i];
            double x = p.dx;
            double y = p.dy;

            if (x < 0 || x > screenSize.width) {
              _directions[i] = Offset(-_directions[i].dx, _directions[i].dy);
            }
            if (y < 0 || y > screenSize.height) {
              _directions[i] = Offset(_directions[i].dx, -_directions[i].dy);
            }

            _nodes[i] = Offset(
              p.dx.clamp(0, screenSize.width),
              p.dy.clamp(0, screenSize.height),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_initialized && constraints.maxWidth > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _initializeNodes(constraints.biggest);
              });
            }
          });
        }
        return CustomPaint(
          size: constraints.biggest,
          painter: DAGPainter(nodes: _nodes),
        );
      },
    );
  }
}

class DAGPainter extends CustomPainter {
  final List<Offset> nodes;

  DAGPainter({required this.nodes});

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1.5;

    for (int i = 1; i < nodes.length; i++) {
      int parentIndex = (i - 1) ~/ 2;
      canvas.drawLine(nodes[i], nodes[parentIndex], linePaint);
    }

    for (var point in nodes) {
      double radius = 5 + (point.dx + point.dy) % 4;
      canvas.drawCircle(point, radius, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// -------------------- DATA MODELS --------------------
class LandlordHomePage extends StatefulWidget {
  const LandlordHomePage({super.key});

  @override
  LandlordHomePageState createState() => LandlordHomePageState();
}

class LandlordHomePageState extends State<LandlordHomePage> {
  int _currentIndex = 0;
  final List<int> _navigationStack = [0]; // history of visited tabs

  // The pages are initialized in initState so they can receive the custom callback
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Initialize pages, passing the custom back handler to each root tab
    _pages = [
      LandlordProfilePage(
        onBack: () {
          // Custom back logic for profile page
          if (_navigationStack.length > 1) {
            _handleCustomBack();
          } else {
            // Do nothing: stay on this page instead of popping
          }
        },
      ),
      AgreementsPage(onBack: _handleCustomBack),
      RequestsPage(onBack: _handleCustomBack),
      PaymentsPage(onBack: _handleCustomBack),
      SettingsPage(onBack: _handleCustomBack),
    ];
  }

  // Custom back logic for the top navigation bar and device back button
  void _handleCustomBack() {
    if (_navigationStack.length > 1) {
      setState(() {
        _navigationStack.removeLast();
        _currentIndex = _navigationStack.last;
      });
    } else {
      // If at the root of the tab navigation, exit the page/app shell.
      // This is what pops to the "unwanted page" if LandlordHomePage isn't the app root.
      Navigator.pop(context);
    }
  }

  // Handle device back button
  /*Future<bool> _onWillPop() async {
    if (_navigationStack.length > 1) {
      _handleCustomBack(); // Use the custom tab history logic
      return false; // prevent default pop
    }
    return true; // allow app exit
  }*/

  // When bottom nav button is tapped
  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      // Add the new tab index to the history
      _navigationStack.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF141E30),
        body: _pages[_currentIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          backgroundColor: const Color(0xFF1F2C45),
          selectedItemColor: Colors.orange,
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            BottomNavigationBarItem(
              icon: Icon(Icons.description),
              label: 'Agreements',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.request_page),
              label: 'Requests',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.payments),
              label: 'Payments',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
