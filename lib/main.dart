import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:email_validator/email_validator.dart';
import 'package:file_picker/file_picker.dart'; // For picking general documents
import 'package:image_picker/image_picker.dart';
import 'dart:io';

int? role;
String? uid;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

// -------------------- APP ENTRY --------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secure Homes',
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
      home: const LoginPage(),
    );
  }
}

// -------------------- CUSTOM TOP NAV BAR --------------------

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
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.3)),
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
    if (_isSendingResetEmail || _isLoading)
      return; // Prevent multiple clicks if either action is running

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
              color: Colors.white.withOpacity(0.2),
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- ASSIGN CONTROLLERS ---
              CustomTextField(
                hintText: 'Username', // Assuming this is Email
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
                        : Colors.white.withOpacity(0.7),
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
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                      backgroundColor: Colors.teal.withOpacity(0.8),
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
                      backgroundColor: Colors.indigo.withOpacity(0.8),
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
  _TenantRegistrationPageState createState() => _TenantRegistrationPageState();
}

class _TenantRegistrationPageState extends State<TenantRegistrationPage> {
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
                                color: Colors.white.withOpacity(0.2),
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
  _LandlordRegistrationPageState createState() =>
      _LandlordRegistrationPageState();
}

class _LandlordRegistrationPageState extends State<LandlordRegistrationPage> {
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
      print("--- Checking profile name uniqueness for: $profileName ---");
      final querySnapshot = await FirebaseFirestore.instance
          .collection('UserIds')
          .where(
        'UserId',
        isEqualTo: profileName,
      ) // Check against the trimmed profileName
          .limit(1) // We only need to know if at least one exists
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        print("--- Profile name '$profileName' already exists. ---");
        // If docs list is not empty, the profile name is taken
        throw Exception('Profile name already taken. Please choose another.');
      }
      print("--- Profile name '$profileName' is unique. Proceeding... ---");
      // --- END PROFILE NAME UNIQUENESS CHECK ---

      // 1. Register with Firebase Auth (Only proceeds if profile name is unique)
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      String uid = userCredential.user!.uid;
      print("--- FirebaseAuth SUCCEEDED - UID: $uid ---");

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
      print("--- Firestore set (landlord collection) SUCCEEDED ---");

      // 3. Store unique profile name in UserIds collection (AFTER landlord data is saved)
      await FirebaseFirestore.instance.collection('UserIds').add({
        'UserId': profileName, // Store the unique, trimmed profile name
      });
      print("--- Firestore add (UserIds collection) SUCCEEDED ---");

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
        print("--- _registerLandlord: Navigating back... ---");
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        print("--- _registerLandlord: NOT navigating (unmounted) ---");
      }
    } catch (e) {
      print("--- _registerLandlord: *** CATCH BLOCK ENTERED *** ---");
      print("--- _registerLandlord: Error: $e ---");
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
      print(
        "--- _registerLandlord: Error message determined: $errorMessage ---",
      );

      // Show error Snackbar
      print("--- _registerLandlord: Showing ERROR Snackbar ---");
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage), // Plain text
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      print("--- _registerLandlord: Entering FINALLY block ---");
      // Ensure loading state is reset ONLY if the widget is still mounted
      if (mounted) {
        print("--- _registerLandlord: Setting isLoading = false ---");
        setState(() {
          _isLoading = false;
          print(
            "--- _registerLandlord: setState (isLoading=false) completed ---",
          );
        });
      } else {
        print("--- _registerLandlord: NOT setting isLoading (unmounted) ---");
      }
      print("--- _registerLandlord: Exiting FINALLY block ---");
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
                                color: Colors.white.withOpacity(0.2),
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
        color: Colors.white.withOpacity(0.95),
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
          dropdownColor: Colors.white.withOpacity(0.95),
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
  _InfiniteDAGBackgroundState createState() => _InfiniteDAGBackgroundState();
}

class _InfiniteDAGBackgroundState extends State<InfiniteDAGBackground>
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
      ..color = Colors.white.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
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
  _LandlordHomePageState createState() => _LandlordHomePageState();
}

class _LandlordHomePageState extends State<LandlordHomePage> {
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
  Future<bool> _onWillPop() async {
    if (_navigationStack.length > 1) {
      _handleCustomBack(); // Use the custom tab history logic
      return false; // prevent default pop
    }
    return true; // allow app exit
  }

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
    return WillPopScope(
      onWillPop: _onWillPop,
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

class LandlordProfilePage extends StatefulWidget {
  final VoidCallback onBack; // Assuming this is passed in

  const LandlordProfilePage({super.key, required this.onBack});

  @override
  _LandlordProfilePageState createState() => _LandlordProfilePageState();
}

class _LandlordProfilePageState extends State<LandlordProfilePage> {
  // --- State variables ---
  List<DocumentField> userDocuments = [DocumentField()];
  List<PropertyCard> propertyCards = [
    PropertyCard(documents: [DocumentField()]),
  ];
  // List<XFile> houseImages = []; // REMOVED Global list
  bool _isUploadingAll = false;
  String? _landlordName;
  String? _profilePicUrl;

  final List<String> userDocOptions = [
    "Aadhar",
    "PAN",
    "License",
    "Birth Certificate",
  ];
  final List<String> propertyDocOptions = [
    "Property Tax Receipt",
    "Land Ownership Proof",
    "Electricity Bill",
    "Water Bill",
  ];
  // Removed global image picker instance

  // Dummy tenant reviews remain
  final List<Map<String, dynamic>> tenantReviews = [
    {
      "tenant": "John Doe",
      "rating": 5,
      "comment": "Great landlord! Very responsive and cooperative.",
    },
    {
      "tenant": "Emma Wilson",
      "rating": 4,
      "comment": "Nice experience overall. The property was well maintained.",
    },
    {
      "tenant": "Michael Smith",
      "rating": 5,
      "comment": "Best renting experience ever. Highly recommend!",
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchLandlordData();
  }

  Future<void> _fetchLandlordData() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Fetch Name
    try {
      DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(uid)
          .get();
      if (landlordDoc.exists && mounted) {
        var data = landlordDoc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('fullName')) {
          setState(() {
            _landlordName = data['fullName'] as String?;
          });
        }
      }
    } catch (e) {
      print("Error fetching landlord name: $e");
    }
    // Fetch Profile Picture URL
    try {
      ListResult result = await FirebaseStorage.instance
          .ref('$uid/profile_pic/')
          .list(const ListOptions(maxResults: 1));
      if (result.items.isNotEmpty && mounted) {
        String url = await result.items.first.getDownloadURL();
        setState(() {
          _profilePicUrl = url;
        });
      } else {
        print("No profile picture found in storage.");
      }
    } catch (e) {
      print("Error fetching profile picture: $e");
    }
  }

  @override
  void dispose() {
    for (var card in propertyCards) {
      card.dispose();
    }
    super.dispose();
  }

  Future<File?> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  // --- MODIFIED: Function to pick images FOR A SPECIFIC PROPERTY ---
  Future<void> _pickHouseImages(int propertyIndex) async {
    // Check bounds
    if (propertyIndex < 0 || propertyIndex >= propertyCards.length) return;

    final ImagePicker picker = ImagePicker(); // Create picker instance locally
    final List<XFile> pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty && mounted) {
      setState(() {
        // Add picked images to the specific property card's list
        propertyCards[propertyIndex].houseImages.addAll(pickedFiles);
      });
    }
  }

  Future<String?> _uploadFileToStorage(File file, String storagePath) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      print("Uploaded ${file.path} to $storagePath. URL: $downloadUrl");
      return downloadUrl;
    } catch (e) {
      print("Error uploading file $storagePath: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload ${storagePath.split('/').last}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  void _resetFormState() {
    setState(() {
      userDocuments = [DocumentField()];
      for (var card in propertyCards) {
        card.dispose();
      }
      propertyCards = [
        PropertyCard(documents: [DocumentField()]),
      ]; // Creates new cards, implicitly clearing images
      _isUploadingAll = false;
    });
    print("--- Form state reset ---");
  }

  Future<void> _uploadAllData() async {
    if (_isUploadingAll) return;

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not logged in'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isUploadingAll = true;
    });
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Uploading all data Please wait'),
        duration: Duration(minutes: 5),
      ),
    );

    bool uploadErrorOccurred = false;
    List<String> userDocUrls = [];
    List<Map<String, dynamic>> propertiesData = [];

    try {
      // 1. Upload User Documents
      print("--- Uploading User Documents ---");
      for (int i = 0; i < userDocuments.length; i++) {
        DocumentField docField = userDocuments[i];
        if (docField.selectedDoc != null && docField.pickedFile != null) {
          String fileName = docField.selectedDoc!;
          String path = '$uid/user_docs/$fileName';
          String? url = await _uploadFileToStorage(docField.pickedFile!, path);
          if (url != null) {
            userDocUrls.add(url);
            docField.downloadUrl = url;
          } else {
            uploadErrorOccurred = true;
          }
        } else if (docField.selectedDoc != null ||
            docField.pickedFile != null) {
          print("Skipping incomplete user document at index $i.");
          // uploadErrorOccurred = true; // Optional: Treat incomplete as error
          // throw Exception("Please pick a file for selected user document '${docField.selectedDoc ?? '...'}'");
        } else {
          print("Skipping empty user document row at index $i.");
        }
      }
      print("--- Finished User Documents ---");

      // 2. Upload Property Documents, Images and Collect Property Data
      print("--- Uploading Property Data, Documents & Images ---");
      for (int i = 0; i < propertyCards.length; i++) {
        PropertyCard card = propertyCards[i];
        List<String> propertyDocUrls = [];
        List<String> currentPropertyImageUrls =
        []; // List for this property's images
        String propertyFolderName = 'property${i + 1}';

        // Upload property docs
        for (int j = 0; j < card.documents.length; j++) {
          DocumentField docField = card.documents[j];
          if (docField.selectedDoc != null && docField.pickedFile != null) {
            String fileName = docField.selectedDoc!;
            String path =
                '$uid/$propertyFolderName/$fileName'; // Docs still go in property folder root
            String? url = await _uploadFileToStorage(
              docField.pickedFile!,
              path,
            );
            if (url != null) {
              propertyDocUrls.add(url);
              docField.downloadUrl = url;
            } else {
              uploadErrorOccurred = true;
            }
          } else if (docField.selectedDoc != null ||
              docField.pickedFile != null) {
            print(
              "Skipping incomplete property document at index $j for property $i.",
            );
          } else {
            print(
              "Skipping empty property document row at index $j for property $i.",
            );
          }
        }

        // --- Upload house images for THIS property ---
        print("--- Uploading House Images for Property ${i + 1} ---");
        if (card.houseImages.isNotEmpty) {
          for (int k = 0; k < card.houseImages.length; k++) {
            XFile imageFile = card.houseImages[k];
            String imgFileName =
                'house_image_$k.${imageFile.path.split('.').last}';
            // --- UPDATED PATH: uid/propertyX/images/imagename ---
            String imgPath = '$uid/$propertyFolderName/images/$imgFileName';
            String? imgUrl = await _uploadFileToStorage(
              File(imageFile.path),
              imgPath,
            );
            if (imgUrl != null) {
              currentPropertyImageUrls.add(imgUrl);
            } else {
              uploadErrorOccurred = true;
            }
          }
        } else {
          print("--- No house images to upload for Property ${i + 1} ---");
        }
        print("--- Finished House Images for Property ${i + 1} ---");

        // Collect details including the image URLs for this property
        propertiesData.add({
          'roomType': card.roomTypeController.text.trim(),
          'location': card.locationController.text.trim(),
          'rent': card.rentController.text.trim(),
          'maxOccupancy': card.maxOccupancyController.text.trim(),
          'documentUrls': propertyDocUrls,
          'houseImageUrls': currentPropertyImageUrls, // Add image URLs here
        });
      }
      print("--- Finished Property Data, Documents & Images ---");

      // 3. Upload House Images (REMOVED - now handled per property)

      // 4. Save to Firestore (Structure now includes image URLs per property)
      if (!uploadErrorOccurred) {
        print("--- Saving data to Firestore collection 'house' doc '$uid' ---");
        await FirebaseFirestore.instance.collection('house').doc(uid).set({
          'properties':
          propertiesData, // This list now contains image URLs within each map
          // 'houseImageUrls': houseImageUrls, // REMOVED top-level list
          'userDocumentUrls': userDocUrls,
        }, SetOptions(merge: true));
        print("--- Firestore set SUCCEEDED ---");

        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('All data uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _resetFormState(); // Reset form state on success
      } else {
        print("--- Firestore save skipped due to upload errors ---");
        throw Exception('Some file uploads failed Check logs');
      }
    } catch (e) {
      print("--- _uploadAllData FAILED: $e ---");
      if (mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Upload failed ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAll = false;
        });
      }
    }
  }
  // --- END FINAL UPLOAD FUNCTION ---

  @override
  Widget build(BuildContext context) {
    // --- UI CHANGES MINIMIZED, MAINLY REMOVING/MOVING IMAGE SECTION ---
    return WillPopScope(
      onWillPop: () async {
        widget.onBack();
        return false;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Container(color: const Color(0xFF141E30)),
            const TwinklingStarBackground(),
            SafeArea(
              minimum: EdgeInsets.zero,
              child: Column(
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: 'My Profile',
                    onBack: widget.onBack,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.white12,
                            backgroundImage: _profilePicUrl != null
                                ? NetworkImage(_profilePicUrl!)
                                : null,
                            child: _profilePicUrl == null
                                ? const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.deepPurple,
                            )
                                : null,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _landlordName ?? "Landlord Name",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            "Validate User",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            itemCount: userDocuments.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildUserDocField(i),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                userDocuments.add(DocumentField());
                              });
                            },
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              "Add Document",
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 40),
                          Text(
                            "Validate Property",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            itemCount: propertyCards.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildPropertyCard(
                                i,
                              ), // This now includes house images section internally
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                propertyCards.add(
                                  PropertyCard(documents: [DocumentField()]),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              "Add Property",
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // --- REMOVED Standalone House Images Section ---

                          // --- FINAL UPLOAD BUTTON (MOVED HERE) ---
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isUploadingAll
                                  ? null
                                  : _uploadAllData,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                disabledBackgroundColor: Colors.grey.shade600,
                              ),
                              child: _isUploadingAll
                                  ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                                  : const Text(
                                "SAVE & UPLOAD ALL",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40), // Space after button
                          // --- END FINAL UPLOAD BUTTON ---
                          Text(
                            "Tenant Reviews",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            itemCount: tenantReviews.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final review = tenantReviews[index];
                              // --- Original Tenant Review Card ---
                              return Card(
                                color: Colors.white.withOpacity(0.08),
                                margin: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.person,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            review["tenant"],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: List.generate(
                                          review["rating"],
                                              (i) => const Icon(
                                            Icons.star,
                                            color: Colors.amber,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        review["comment"],
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              // --- End Original Tenant Review Card ---
                            },
                          ),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDocField(int index) {
    final docField = userDocuments[index];
    final selectedDocs = userDocuments
        .map((e) => e.selectedDoc)
        .whereType<String>()
        .toList();
    final availableOptions = userDocOptions
        .where(
          (doc) => !selectedDocs.contains(doc) || doc == docField.selectedDoc,
    )
        .toList();

    return GlassmorphismContainer(
      opacity: 0.1,
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: docField.selectedDoc,
              hint: const Text(
                "Select Document",
                style: TextStyle(color: Colors.white),
              ),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: availableOptions
                  .map((doc) => DropdownMenuItem(value: doc, child: Text(doc)))
                  .toList(),
              onChanged: (val) {
                setState(() => docField.selectedDoc = val);
              },
            ),
          ),
          const SizedBox(width: 8),
          if (docField.pickedFile != null) ...[
            Expanded(
              child: Text(
                docField.pickedFile!.path.split('/').last,
                style: const TextStyle(color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54),
              onPressed: () => setState(() => docField.pickedFile = null),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: docField.selectedDoc == null
                  ? null
                  : () async {
                File? picked = await _pickDocument();
                if (picked != null) {
                  setState(() => docField.pickedFile = picked);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                disabledBackgroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 14),
              ),
              child: const Text(
                "Pick File",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: "Remove this document row",
            onPressed: () => setState(() => userDocuments.removeAt(index)),
          ),
        ],
      ),
    );
  }

  // --- UPDATED PROPERTY CARD BUILDER (Includes House Images section) ---
  Widget _buildPropertyCard(int index) {
    final property = propertyCards[index];

    return GlassmorphismContainer(
      opacity: 0.12,
      padding: const EdgeInsets.all(12),
      borderRadius: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.home, color: Colors.orange.shade700),
              const SizedBox(width: 10),
              const Text(
                "Property Details & Validation",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: "Remove this property card",
                onPressed: () {
                  property.dispose();
                  setState(() => propertyCards.removeAt(index));
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          CustomTextField(
            controller: property.roomTypeController,
            hintText: "Room Type (e.g., 1BHK, 2BHK)",
          ),
          const SizedBox(height: 10),
          CustomTextField(
            controller: property.locationController,
            hintText: "Location (Area/Street)",
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: property.rentController,
                  hintText: "Rent Amount",
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomTextField(
                  controller: property.maxOccupancyController,
                  hintText: "Max Occupancy",
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            "Property Documents:",
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 5),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: property.documents
                .asMap()
                .entries
                .map((entry) => _buildPropertyDocField(index, entry.key))
                .toList(),
          ),
          const SizedBox(height: 10),
          Center(
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  property.documents.add(DocumentField());
                });
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                "Add Document",
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
              ),
            ),
          ),

          // --- ADDED House Images Section WITHIN Property Card ---
          const SizedBox(height: 20),
          const Text("House Images:", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          if (property.houseImages.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: property.houseImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, imgIndex) {
                  final imageFile = property.houseImages[imgIndex];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(imageFile.path),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                width: 100,
                                height: 100,
                                color: Colors.white12,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.white54,
                                  size: 50,
                                ),
                              ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              property.houseImages.removeAt(imgIndex);
                            });
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          else
            const Text(
              "No images added for this property yet.",
              style: TextStyle(color: Colors.white70),
            ),
          const SizedBox(height: 10),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _pickHouseImages(
                index,
              ), // Call image picker for THIS property
              icon: const Icon(Icons.add_a_photo, color: Colors.white),
              label: const Text(
                "Add Image",
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
              ),
            ),
          ),

          // --- END House Images Section ---
        ],
      ),
    );
  }

  Widget _buildPropertyDocField(int propIndex, int docIndex) {
    final property = propertyCards[propIndex];
    final docField = property.documents[docIndex];
    final selectedDocs = property.documents
        .map((e) => e.selectedDoc)
        .whereType<String>()
        .toList();
    final availableOptions = propertyDocOptions
        .where(
          (doc) => !selectedDocs.contains(doc) || doc == docField.selectedDoc,
    )
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: docField.selectedDoc,
              hint: const Text(
                "Select Document",
                style: TextStyle(color: Colors.white),
              ),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: availableOptions
                  .map((doc) => DropdownMenuItem(value: doc, child: Text(doc)))
                  .toList(),
              onChanged: (val) {
                setState(() => docField.selectedDoc = val);
              },
            ),
          ),
          const SizedBox(width: 8),
          if (docField.pickedFile != null) ...[
            Expanded(
              child: Text(
                docField.pickedFile!.path.split('/').last,
                style: const TextStyle(color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54),
              onPressed: () => setState(() => docField.pickedFile = null),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: docField.selectedDoc == null
                  ? null
                  : () async {
                File? picked = await _pickDocument();
                if (picked != null) {
                  setState(() => docField.pickedFile = picked);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                disabledBackgroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 14),
              ),
              child: const Text(
                "Pick File",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: "Remove this document",
            onPressed: () {
              setState(() {
                property.documents.removeAt(docIndex);
              });
            },
          ),
        ],
      ),
    );
  }
} // End of _LandlordProfilePageState

class RequestsPage extends StatefulWidget {
  final VoidCallback onBack;
  const RequestsPage({super.key, required this.onBack});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  final List<Map<String, String>> pendingRequests = [
    {"name": "John Doe", "property": "Sunset Apartments"},
    {"name": "Emma Wilson", "property": "Greenwood Villa"},
    {"name": "Michael Smith", "property": "Oceanview Residences"},
  ];

  final List<Map<String, String>> acceptedRequests = [];

  void _handleAction(
      BuildContext context,
      Map<String, String> tenant,
      bool accept,
      ) async {
    final action = accept ? "accept" : "decline";

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        title: Text(
          "Confirm $action",
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          "Are you sure you want to $action ${tenant['name']}'s request?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              action.toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        pendingRequests.remove(tenant);
        if (accept) acceptedRequests.add(tenant);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background layers
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),

          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: "Requests",
                    onBack: widget.onBack,
                  ),

                  const Padding(
                    padding: EdgeInsets.only(top: 8.0, bottom: 10.0),
                    child: Center(
                      child: Text(
                        "Pending Requests",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // Pending Requests List
                  ...pendingRequests.map(
                        (tenant) => Card(
                      color: Colors.white.withOpacity(0.1),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        title: Text(
                          tenant["name"]!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          tenant["property"]!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Tenantsearch_ProfilePage(
                                tenantName: tenant["name"]!,
                                propertyName: tenant["property"]!,
                                onBack: () => Navigator.pop(context),
                              ),
                            ),
                          );
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () =>
                                  _handleAction(context, tenant, true),
                              child: const Text("Accept"),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () =>
                                  _handleAction(context, tenant, false),
                              child: const Text("Decline"),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Accepted Requests Section
                  if (acceptedRequests.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 20.0, bottom: 10),
                      child: Center(
                        child: Text(
                          "Accepted Requests",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    ...acceptedRequests.map(
                          (tenant) => Card(
                        color: Colors.green.withOpacity(0.15),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          title: Text(
                            tenant["name"]!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            tenant["property"]!,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Tenantsearch_ProfilePage(
                                  tenantName: tenant["name"]!,
                                  propertyName: tenant["property"]!,
                                  onBack: () => Navigator.pop(context),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- SETTINGS PAGE --------------------
class GlassmorphismContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final double opacity;
  final double blur;
  final VoidCallback? onTap;

  const GlassmorphismContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius = 15.0,
    this.opacity =
    0.05, // Default opacity lowered to 0.05 for more transparency
    this.blur = 10.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// LOGOUT CONFIRMATION DIALOG
// ====================================================================

class LogoutConfirmationDialog extends StatelessWidget {
  const LogoutConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: GlassmorphismContainer(
        borderRadius: 20.0,
        opacity: 0.12, // Opacity reduced from 0.2 to 0.12
        blur: 15.0,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Confirm Logout',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Are you sure you want to log out of Secure Homes?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // YES button (Proceed to Logout)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // 1. Close the confirmation dialog
                      Navigator.pop(context);

                      // 2. Proceed with logout (navigate to LoginPage and clear stack)
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                            (Route<dynamic> route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'YES, Logout',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                // NO button (Cancel)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Close the dialog (Cancel the logout)
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'NO, Stay',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TwinklingStarBackground extends StatefulWidget {
  const TwinklingStarBackground({super.key});

  @override
  State<TwinklingStarBackground> createState() =>
      _TwinklingStarBackgroundState();
}

class _TwinklingStarBackgroundState extends State<TwinklingStarBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final int _numberOfStars = 80; // INCREASED DENSITY from 50
  late List<Map<String, dynamic>> _stars;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        seconds: 15,
      ), // Longer duration for subtle movement
    )..repeat();

    // Initialize stars with random properties
    _stars = List.generate(_numberOfStars, (index) => _createRandomStar());
  }

  Map<String, dynamic> _createRandomStar() {
    return {
      'offset': Offset(Random().nextDouble(), Random().nextDouble()),
      'size':
      2.0 +
          Random().nextDouble() *
              3.0, // INCREASED SIZE range from 1.5-4.0 to 2.0-5.0
      'duration': Duration(
        milliseconds: 1500 + Random().nextInt(1500),
      ), // Twinkle duration
      'delay': Duration(
        milliseconds: Random().nextInt(10000),
      ), // Starting delay
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: _stars.map((star) {
              final double screenWidth = MediaQuery.of(context).size.width;
              final double screenHeight = MediaQuery.of(context).size.height;

              // Calculate twinkling effect based on controller time and star properties
              final double timeInMilliseconds =
                  _controller.value * _controller.duration!.inMilliseconds;
              final double timeOffset =
                  (timeInMilliseconds + star['delay'].inMilliseconds) /
                      star['duration'].inMilliseconds;

              // Use a sine wave for blinking effect, slightly offset to prevent perfect synchronization
              final double opacityFactor = (sin(timeOffset * pi * 2) + 1) / 2;

              // INCREASED INTENSITY/OPACITY: Opacity range from very dim (0.1) to bright (0.8)
              final double opacity =
                  0.1 +
                      (0.7 * opacityFactor); // Multiplier changed from 0.5 to 0.7

              return Positioned(
                left: star['offset'].dx * screenWidth,
                top: star['offset'].dy * screenHeight,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: star['size'],
                    height: star['size'],
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.5 * opacity),
                          blurRadius: star['size'] / 2,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class SettingsPage extends StatelessWidget {
  final VoidCallback onBack;
  const SettingsPage({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> _settingsOptions = [
      {
        'title': 'Edit Profile',
        'icon': Icons.person_outline,
        'color': Colors.blue,
        'action': (BuildContext context) => _showEditProfileDialog(context),
      },
      {
        'title': 'Change Password',
        'icon': Icons.lock_outline,
        'color': Colors.orange,
        'action': (BuildContext context) => _showChangePasswordDialog(context),
      },
      {
        'title': 'Notification Preferences',
        'icon': Icons.notifications_none,
        'color': Colors.green,
        'action': (BuildContext context) => print('Navigate to Notifications'),
      },
      {
        'title': 'Privacy & Security',
        'icon': Icons.security,
        'color': Colors.purple,
        'action': (BuildContext context) => print('Navigate to Privacy'),
      },
      {
        'title': 'Help & Support',
        'icon': Icons.help_outline,
        'color': Colors.yellow.shade700,
        'action': (BuildContext context) => _showHelpDialog(context),
      },
    ];

    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "Settings",
                  onBack: onBack,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Account Settings",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        ..._settingsOptions.map((option) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassmorphismContainer(
                              borderRadius: 15,
                              opacity: 0.08,
                              onTap: () => option['action'](context),
                              child: Row(
                                children: [
                                  Icon(
                                    option['icon'],
                                    color: option['color'],
                                    size: 30,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Text(
                                      option['title'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white54,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),

                        const SizedBox(height: 30),

                        // -------------------- LOGOUT BUTTON --------------------
                        GlassmorphismContainer(
                          borderRadius: 15,
                          opacity: 0.08,
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) =>
                                  AlertDialog(
                                    backgroundColor: const Color(0xFF1E2A47),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    title: const Text(
                                      "Confirm Logout",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: const Text(
                                      "Are you sure you want to logout?",
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text(
                                          "Cancel",
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                        ),
                                        onPressed: () {
                                          Navigator.pop(dialogContext);
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const LoginPage(),
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          "Logout",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.logout,
                                color: Colors.redAccent,
                                size: 30,
                              ),
                              SizedBox(width: 15),
                              Text(
                                'LOGOUT',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
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

  // ---------------------- HELP & SUPPORT DIALOG ----------------------
  static void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Help & Support",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Contact Admin:\n\n📞 +91 9497320928\n📞 +91 8281258530",
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Close",
              style: TextStyle(color: Colors.blueAccent),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------- EDIT PROFILE DIALOG ----------------------
  // --- UPDATED EDIT PROFILE DIALOG ---
  // IMPORTANT: Assumes necessary imports exist: dart:io, flutter/material.dart,
  // image_picker, firebase_auth, cloud_firestore, firebase_storage
  // Also assumes _buildInputField is defined statically as provided.

  static void _showEditProfileDialog(BuildContext context) {
    // Keep controllers for fields being edited
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController =
    TextEditingController(); // Represents profileName (UserId)
    final TextEditingController phoneController = TextEditingController();
    // Removed email and address controllers

    // Variables for image picking and loading state need to be managed within StatefulBuilder
    XFile? _pickedImageFile;
    bool _isUpdating = false;

    // --- Pre-fetch current data (Cannot be done easily in static function without passing data) ---
    // --- User will have to re-type existing values or logic needs adjustment ---

    showDialog(
      context: context,
      // Use StatefulBuilder to manage the state within the dialog
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, stfSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47), // Keep original color
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ), // Keep shape
            title: const Text(
              // Keep title style
              "Edit Profile",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      // --- Image Picking Logic ---
                      if (_isUpdating) return;
                      final ImagePicker picker = ImagePicker();
                      try {
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          stfSetState(() {
                            // Use StatefulBuilder's setState
                            _pickedImageFile = image;
                          });
                          print("Image picked: ${image.path}");
                        } else {
                          print("Image picking cancelled.");
                        }
                      } catch (e) {
                        print("Error picking image: $e");
                        // Show error Snackbar using the original context
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to pick image'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: CircleAvatar(
                      // Keep original CircleAvatar structure
                      radius: 40,
                      backgroundColor:
                      Colors.grey.shade700, // Keep placeholder background
                      backgroundImage: _pickedImageFile != null
                          ? FileImage(
                        File(_pickedImageFile!.path),
                      ) // Show picked file
                      // --- TODO: Fetch and display current image here if desired, requires passing URL or fetching ---
                          : const AssetImage('assets/profile_placeholder.png')
                      as ImageProvider, // Keep placeholder
                      child: const Align(
                        // Keep edit icon overlay
                        alignment: Alignment.bottomRight,
                        child: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          radius: 14,
                          child: Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15), // Keep spacing
                  // Use provided _buildInputField
                  _buildInputField(nameController, "Full Name"),
                  _buildInputField(
                    idController,
                    "User ID",
                  ), // Profile Name (UserId)
                  _buildInputField(phoneController, "Phone Number"),
                  // Email and Address fields removed as requested
                ],
              ),
            ),
            actions: [
              // Keep original actions structure
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext), // Use dialogContext
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ), // Keep style
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Keep color
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: _isUpdating
                    ? null
                    : () async {
                  // --- UPDATE LOGIC ---
                  stfSetState(() {
                    _isUpdating = true;
                  });
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(dialogContext);

                  final String? uid =
                      FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Error Not logged in'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isUpdating = false;
                    });
                    return;
                  }

                  try {
                    // 1. Upload Image if picked
                    if (_pickedImageFile != null) {
                      print("Uploading profile picture...");
                      // Path: uid/profile_pic/profile_image.jpg (overwrites previous)
                      String filePath =
                          '$uid/profile_pic/profile_image.jpg';
                      Reference storageRef = FirebaseStorage.instance
                          .ref()
                          .child(filePath);
                      UploadTask uploadTask = storageRef.putFile(
                        File(_pickedImageFile!.path),
                      );
                      await uploadTask; // Wait for upload to complete
                      print("Profile picture uploaded successfully.");
                      // imageUrl = await snapshot.ref.getDownloadURL(); // Get URL only if needed
                    }

                    // 2. Prepare data for Firestore update
                    final String newFullName = nameController.text.trim();
                    final String newProfileName = idController.text
                        .trim(); // User ID field is Profile Name
                    final String newPhoneNumber = phoneController.text
                        .trim();

                    Map<String, dynamic> updateData = {};
                    if (newFullName.isNotEmpty)
                      updateData['fullName'] = newFullName;
                    if (newProfileName.isNotEmpty)
                      updateData['profileName'] = newProfileName;
                    if (newPhoneNumber.isNotEmpty)
                      updateData['phoneNumber'] = newPhoneNumber;

                    // 3. Update Firestore if there's data to update
                    if (updateData.isNotEmpty) {
                      print(
                        "Updating Firestore for UID: $uid with data: $updateData",
                      );
                      // Assuming user is landlord based on function context
                      await FirebaseFirestore.instance
                          .collection('landlord')
                          .doc(uid)
                          .update(updateData);
                      print("Firestore update successful.");

                      // 4. Update unique UserId collection IF profileName changed
                      // Warning: This only adds, doesn't check uniqueness thoroughly again or remove old.
                      if (newProfileName.isNotEmpty) {
                        // Optional: Re-check uniqueness before adding for robustness
                        final checkSnap = await FirebaseFirestore.instance
                            .collection('UserIds')
                            .where('UserId', isEqualTo: newProfileName)
                            .limit(1)
                            .get();
                        if (checkSnap.docs.isEmpty) {
                          print(
                            "Adding new unique profile name to UserIds collection.",
                          );
                          await FirebaseFirestore.instance
                              .collection('UserIds')
                              .add({'UserId': newProfileName});
                          // Note: Does not remove the old profile name.
                        } else {
                          print(
                            "New profile name might already exist (race condition/old data?). Not adding again.",
                          );
                          // Decide handling: ignore (current), or throw error?
                          // throw Exception('Profile name already exists');
                        }
                      }
                    } else if (_pickedImageFile != null) {
                      print(
                        "Only profile picture was updated, skipping Firestore field update.",
                      );
                    } else {
                      print(
                        "No fields changed and no new picture, skipping updates.",
                      );
                    }

                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    navigator.pop(); // Close dialog on success
                  } catch (e) {
                    print("Error updating profile: $e");
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Update failed ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    // Keep dialog open on error
                  } finally {
                    // Ensure loading state is reset
                    if (navigator.context.mounted) {
                      stfSetState(() {
                        _isUpdating = false;
                      });
                    }
                  }
                },
                child:
                _isUpdating // Show loading indicator or text
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  "Update",
                  style: TextStyle(color: Colors.white),
                ), // Keep style
              ),
            ],
          );
        },
      ),
    );
  }

  // --- UPDATED CHANGE PASSWORD DIALOG ---
  static void _showChangePasswordDialog(BuildContext context) {
    // Removed oldPassController
    final TextEditingController newPassController = TextEditingController();
    final TextEditingController confirmPassController = TextEditingController();
    bool _isChangingPassword = false; // Loading state

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        // Use StatefulBuilder for loading state
        builder: (stfContext, stfSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47), // Keep style
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ), // Keep style
            title: const Text(
              // Keep style
              "Change Password",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Removed old password field
                  _buildInputField(
                    newPassController,
                    "New Password",
                    isPassword: true,
                  ),
                  _buildInputField(
                    confirmPassController,
                    "Confirm Password",
                    isPassword: true,
                  ),
                ],
              ),
            ),
            actions: [
              // Keep style
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent, // Keep style
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: _isChangingPassword
                    ? null
                    : () async {
                  // --- Simplified Password Change Logic ---
                  stfSetState(() {
                    _isChangingPassword = true;
                  });
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(dialogContext);

                  final String newPassword =
                      newPassController.text; // No trim
                  final String confirmPassword =
                      confirmPassController.text; // No trim

                  // Validation
                  if (newPassword.isEmpty || confirmPassword.isEmpty) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Please fill both password fields'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }
                  if (newPassword != confirmPassword) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('New passwords do not match'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }
                  // Password complexity rules
                  if (newPassword.length < 6) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'New password must be at least 6 characters long',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }
                  if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(newPassword)) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'New password must contain only letters and numbers',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }

                  User? user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Error Not logged in'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }

                  try {
                    // Directly update password (no re-authentication)
                    print("Attempting to update password directly...");
                    await user.updatePassword(newPassword);
                    print(
                      "Password updated successfully via direct method!",
                    );

                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Password changed successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    navigator.pop(); // Close dialog on success
                  } on FirebaseAuthException catch (e) {
                    print(
                      "Error changing password directly: ${e.code} - ${e.message}",
                    );
                    String errorMsg =
                        'Failed to change password Please try again'; // Default
                    // Handle common errors from direct update
                    if (e.code == 'weak-password') {
                      errorMsg = 'New password is too weak';
                    } else if (e.code == 'requires-recent-login') {
                      // This error CAN still happen even without explicitly asking for re-auth
                      errorMsg =
                      'This action requires recent login Please log out and log in again';
                    } else {
                      errorMsg = 'Error ${e.message ?? e.code}';
                    }
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(errorMsg),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } catch (e) {
                    print("Generic error changing password: $e");
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to change password ${e.toString()}',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } finally {
                    if (navigator.context.mounted) {
                      stfSetState(() {
                        _isChangingPassword = false;
                      });
                    }
                  }
                },
                child:
                _isChangingPassword // Show loading or text
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  "Update",
                  style: TextStyle(color: Colors.white),
                ), // Keep style
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Provided _buildInputField ---
  static Widget _buildInputField(
      TextEditingController controller,
      String hint, {
        bool isPassword = false,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// -------------------- AGREEMENTS PAGE --------------------
class AgreementsPage extends StatelessWidget {
  final VoidCallback onBack;
  const AgreementsPage({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Dark Background
          Container(color: const Color(0xFF141E30)),

          // 2. Twinkling Star Layer
          const TwinklingStarBackground(),

          SafeArea(
            child: Column(
              children: [
                // 💡 PASS THE onBack CALLBACK HERE
                CustomTopNavBar(
                  showBack: true,
                  title: "Agreements",
                  onBack: onBack,
                ),

                // Screen Title
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Agreements List",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
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

// -------------------- PAYMENTS PAGE --------------------
class PaymentsPage extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage({super.key, required this.onBack});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  String? selectedMethod;
  final TextEditingController _amountController = TextEditingController();

  // Mock transactions (local list)
  final List<Map<String, dynamic>> mockTransactions = [
    {
      'amount': 499,
      'method': 'UPI',
      'date': '18 Oct 2025, 10:45 AM',
      'status': 'Success',
    },
    {
      'amount': 799,
      'method': 'Credit Card',
      'date': '15 Oct 2025, 2:22 PM',
      'status': 'Pending',
    },
    {
      'amount': 299,
      'method': 'Net Banking',
      'date': '10 Oct 2025, 9:10 PM',
      'status': 'Success',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Background layers
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top NavBar
                CustomTopNavBar(
                  showBack: true,
                  title: "Payments",
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 15),

                // Flexible + Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomInset + 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // -------------------- PAYMENT SETUP --------------------


                        // -------------------- TRANSACTION HISTORY --------------------
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Text(
                            "Transaction History",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: mockTransactions.length,
                          itemBuilder: (context, index) {
                            var data = mockTransactions[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                ),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.receipt_long,
                                  color: Colors.orange.shade400,
                                ),
                                title: Text(
                                  "₹${data['amount']} - ${data['method']}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  data['date'],
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                ),
                                trailing: Text(
                                  data['status'],
                                  style: TextStyle(
                                    color: data['status'] == "Success"
                                        ? Colors.greenAccent
                                        : Colors.orangeAccent,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
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

  // -------------------- PAYMENT BUTTON --------------------
  Widget _paymentButton(String title, IconData icon) {
    final bool isSelected = selectedMethod == title;
    return ElevatedButton.icon(
      onPressed: () => setState(() => selectedMethod = title),
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(title, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Colors.orange.shade700
            : Colors.white.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // -------------------- PAYMENT FIELDS --------------------
  Widget _buildPaymentFields(String method) {
    switch (method) {
      case "UPI":
        return Column(
          key: const ValueKey("UPI"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Enter UPI ID (e.g. name@okaxis)"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Credit/Debit Card":
        return Column(
          key: const ValueKey("Card"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Card Number"),
            const SizedBox(height: 10),
            _textField("Card Holder Name"),
            const SizedBox(height: 10),
            _textField("Expiry (MM/YY)"),
            const SizedBox(height: 10),
            _textField("CVV", obscure: true),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Net Banking":
        return Column(
          key: const ValueKey("NetBanking"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Bank Name"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Wallets":
        return Column(
          key: const ValueKey("Wallets"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Wallet Name (Paytm, PhonePe, etc.)"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // -------------------- SHARED INPUTS --------------------
  Widget _textField(String hint, {bool obscure = false}) {
    return TextField(
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
      ),
    );
  }

  Widget _amountField() {
    return TextField(
      controller: _amountController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Enter Amount (₹)",
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
      ),
    );
  }

  Widget _proceedButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: ElevatedButton(
        onPressed: () {
          String amount = _amountController.text.trim();
          if (amount.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please enter an amount")),
            );
            return;
          }

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E2A47),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text(
                "Confirm Payment",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                "Are you sure you want to proceed with ₹$amount via $selectedMethod?",
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Payment of ₹$amount initiated via $selectedMethod",
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    "Confirm",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Center(
          child: Text(
            "Proceed to Pay",
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// -------------------- TENANT PROFILE PAGE (Redirect Target) --------------------

class TenantHomePage extends StatefulWidget {
  const TenantHomePage({super.key});

  @override
  _TenantHomePageState createState() => _TenantHomePageState();
}

class _TenantHomePageState extends State<TenantHomePage> {
  int _currentIndex = 0;
  final List<int> _navigationStack = [0]; // history of visited tabs

  // The pages are initialized in initState so they can receive the custom callback
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Initialize pages, passing the custom back handler to each root tab
    _pages = [
      TenantProfilePage(
        onBack: () {
          // Custom back logic for profile page
          if (_navigationStack.length > 1) {
            _handleCustomBack();
          } else {
            // Do nothing: stay on this page instead of popping
          }
        },
      ),
      AgreementsPage2(onBack: _handleCustomBack),
      SearchPage(onBack: _handleCustomBack),
      RequestsPage2(onBack: _handleCustomBack),
      PaymentsPage2(onBack: _handleCustomBack),
      SettingsPage2(onBack: _handleCustomBack),
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
  Future<bool> _onWillPop() async {
    if (_navigationStack.length > 1) {
      _handleCustomBack(); // Use the custom tab history logic
      return false; // prevent default pop
    }
    return true; // allow app exit
  }

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
    return WillPopScope(
      onWillPop: _onWillPop,
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
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
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

// -------------------- tenant PROFILE PAGE --------------------
// Assuming necessary imports are present: dart:io, dart:ui, flutter/material.dart,
// firebase_auth, cloud_firestore, firebase_storage, file_picker, image_picker
// Also assuming helper classes DocumentField, HomeRental, AnimatedGradientBackground,
// CustomTopNavBar, GlassmorphismContainer are defined correctly elsewhere,
// and DocumentField now includes a 'File? pickedFile' field.

class TenantProfilePage extends StatefulWidget {
  final VoidCallback onBack; // callback for back button

  const TenantProfilePage({super.key, required this.onBack});

  @override
  _TenantProfilePageState createState() => _TenantProfilePageState();
}

class _TenantProfilePageState extends State<TenantProfilePage> {
  List<DocumentField> userDocuments = [DocumentField()];
  final List<String> userDocOptions = [
    "Aadhar",
    "PAN",
    "License",
    "Birth Certificate",
  ];

  // Dummy rented homes data remains
  List<HomeRental> rentedHomes = [
    HomeRental(name: "Sea View Apartment", address: "Beach Road, Goa"),
    HomeRental(name: "Sunshine Villa", address: "MG Road, Bangalore"),
  ];

  // --- State variables for fetched data ---
  String? _tenantName;
  String? _profilePicUrl;
  bool _isLoadingProfile = true; // Loading indicator for initial fetch

  // --- initState to fetch data ---
  @override
  void initState() {
    super.initState();
    _fetchTenantData();
  }

  Future<void> _fetchTenantData() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted)
        setState(() => _isLoadingProfile = false); // Stop loading if no user
      return;
    }

    // Fetch Name from 'tenant' collection
    try {
      DocumentSnapshot tenantDoc = await FirebaseFirestore.instance
          .collection('tenant')
          .doc(uid)
          .get();
      if (tenantDoc.exists && mounted) {
        var data = tenantDoc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('fullName')) {
          setState(() {
            _tenantName = data['fullName'] as String?;
          });
        }
      }
    } catch (e) {
      print("Error fetching tenant name: $e");
    }

    // Fetch Profile Picture URL
    try {
      ListResult result = await FirebaseStorage.instance
          .ref('$uid/profile_pic/')
          .list(const ListOptions(maxResults: 1));
      if (result.items.isNotEmpty && mounted) {
        String url = await result.items.first.getDownloadURL();
        setState(() {
          _profilePicUrl = url;
        });
      } else {
        print("No profile picture found for tenant.");
      }
    } catch (e) {
      print("Error fetching tenant profile picture: $e");
    } finally {
      if (mounted)
        setState(
              () => _isLoadingProfile = false,
        ); // Stop loading after fetching attempts
    }
  }

  // --- Function to pick a document file ---
  Future<File?> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  // --- Function to upload a single file to Firebase Storage ---
  Future<String?> _uploadFileToStorage(File file, String storagePath) async {
    // Show uploading snackbar immediately
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Uploading ${storagePath.split('/').last}...'),
        duration: const Duration(minutes: 1),
      ),
    );

    try {
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      print("Uploaded ${file.path} to $storagePath. URL: $downloadUrl");

      scaffoldMessenger.hideCurrentSnackBar(); // Hide uploading message
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('${storagePath.split('/').last} uploaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
      return downloadUrl;
    } catch (e) {
      print("Error uploading file $storagePath: $e");
      scaffoldMessenger.hideCurrentSnackBar(); // Hide uploading message
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to upload ${storagePath.split('/').last}'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  // --- Function to handle picking AND uploading user document ---
  Future<void> _pickAndUploadUserDocument(int index) async {
    final docField = userDocuments[index];
    if (docField.selectedDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select document type first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    File? pickedFile = await _pickDocument();
    if (pickedFile != null) {
      // Update state to show picked file immediately (optional but good UX)
      setState(() {
        docField.pickedFile = pickedFile;
      });

      // Get UID for path
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Not logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Construct path and upload
      String fileName = docField.selectedDoc!; // Use selected name
      // Add file extension - robustly handle cases where original name might not have one
      String extension = pickedFile.path.split('.').last;
      if (extension.isNotEmpty && extension.length <= 4) {
        // Basic check for valid extension
        fileName += '.$extension';
      }
      String storagePath = '$uid/user_docs/$fileName';

      // Upload the file
      String? downloadUrl = await _uploadFileToStorage(pickedFile, storagePath);
      if (downloadUrl != null && mounted) {
        setState(() {
          docField.downloadUrl = downloadUrl; // Store URL if needed
        });
      } else if (downloadUrl == null && mounted) {
        // If upload failed, maybe clear the picked file?
        // setState(() {
        //   docField.pickedFile = null;
        // });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        widget.onBack();
        return false; // prevent default back navigation
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const AnimatedGradientBackground(), // Keep original background
            SafeArea(
              child: Column(
                children: [
                  // ---------- TOP NAV BAR ----------
                  CustomTopNavBar(
                    // Keep original Top Nav
                    showBack: true,
                    title: 'My Profile',
                    onBack: widget.onBack,
                  ),

                  // ---------- SCROLLABLE CONTENT ----------
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),

                          // ---------- UPDATED PROFILE PIC ----------
                          CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.white12, // Placeholder bg
                            backgroundImage: _profilePicUrl != null
                                ? NetworkImage(_profilePicUrl!)
                                : null,
                            child:
                            _isLoadingProfile // Show loading indicator while fetching
                                ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                                : (_profilePicUrl == null
                                ? const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.deepPurple,
                            )
                                : null), // Show icon if loading done and no URL
                          ),
                          const SizedBox(height: 20),

                          // ---------- UPDATED PROFILE DETAILS ----------
                          Text(
                            _tenantName ??
                                "Tenant Name", // Display fetched name or default
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            // Keep original text format
                            "Agreements for ${rentedHomes.length} Homes",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 30),

                          // ---------- VALIDATE USER ----------
                          Text(
                            // Keep original style
                            "Validate User",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),

                          ListView.builder(
                            // Keep original structure
                            itemCount: userDocuments.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildUserDocField(
                                i,
                              ), // Calls updated build method
                            ),
                          ),

                          const SizedBox(height: 20),

                          ElevatedButton.icon(
                            // Keep original Add button
                            onPressed: () {
                              setState(() {
                                userDocuments.add(DocumentField());
                              });
                            },
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              "Add Document",
                              style: TextStyle(color: Colors.white),
                            ), // Text style for label added
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                            ),
                          ),

                          const SizedBox(height: 40),

                          // ---------- RENTED HOMES (Keep Original Dummy Data) ----------
                          Text(
                            // Keep original style
                            "My Rented Homes",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            // Keep original structure
                            itemCount: rentedHomes.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final home = rentedHomes[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GlassmorphismContainer(
                                  // Keep original style
                                  opacity: 0.1,
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.home,
                                      color: Colors.orange,
                                    ),
                                    title: Text(
                                      home.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      home.address,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 40),

                          // ---------- LANDLORD REVIEWS (Keep Original Dummy Data) ----------
                          Text(
                            // Keep original style
                            "Landlord Reviews",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Column(
                            // Keep original structure
                            children: [
                              _buildReviewCard(
                                landlordName: "Mr. Sharma",
                                rating: 4.5,
                                review:
                                "Great tenant! Paid rent on time and kept the property clean.",
                              ),
                              const SizedBox(height: 12),
                              _buildReviewCard(
                                landlordName: "Mrs. Fernandes",
                                rating: 5.0,
                                review:
                                "Very cooperative and responsible tenant. Would definitely rent again.",
                              ),
                              const SizedBox(height: 12),
                              _buildReviewCard(
                                landlordName: "Mr. Khan",
                                rating: 4.0,
                                review:
                                "Good experience overall. Communication could be a bit faster, but otherwise great!",
                              ),
                            ],
                          ),

                          const SizedBox(
                            height: 60,
                          ), // Keep original bottom padding
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- HELPER WIDGET FOR REVIEWS (Keep Original) ----------
  Widget _buildReviewCard({
    required String landlordName,
    required double rating,
    required String review,
  }) {
    return GlassmorphismContainer(
      opacity: 0.1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  landlordName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Row(
                  children: List.generate(
                    5,
                        (index) => Icon(
                      index < rating.floor()
                          ? Icons.star
                          : index < rating
                          ? Icons.star_half
                          : Icons.star_border,
                      color: Colors.yellow.shade600,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              review,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- UPDATED USER DOCUMENT FIELD ----------------
  Widget _buildUserDocField(int index) {
    final docField = userDocuments[index]; // Use the object from the list
    final selectedDocs = userDocuments
        .map((e) => e.selectedDoc)
        .whereType<String>()
        .toList();
    final availableOptions = userDocOptions
        .where(
          (doc) => !selectedDocs.contains(doc) || doc == docField.selectedDoc,
    )
        .toList();

    return GlassmorphismContainer(
      // Keep original style
      opacity: 0.1,
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              // Keep original style
              isExpanded: true,
              value: docField.selectedDoc,
              hint: const Text(
                "Select Document",
                style: TextStyle(color: Colors.white),
              ),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              underline:
              Container(), // Add this to remove default underline if needed
              items: availableOptions
                  .map(
                    (doc) => DropdownMenuItem(
                  value: doc,
                  child: Text(
                    doc,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
                  .toList(),
              onChanged: (val) {
                setState(() => docField.selectedDoc = val);
              },
            ),
          ),
          const SizedBox(width: 8),

          // --- Show file name or Upload button ---
          if (docField.pickedFile != null) ...[
            Expanded(
              child: Text(
                docField.pickedFile!.path.split('/').last,
                style: const TextStyle(color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54),
              tooltip: "Clear selected file",
              onPressed: () => setState(() => docField.pickedFile = null),
            ),
          ] else ...[
            ElevatedButton(
              // Keep original style
              // --- Call pick and upload function ---
              onPressed: () =>
                  _pickAndUploadUserDocument(index), // Pass the index
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              child: const Text(
                "Upload",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          const SizedBox(width: 8), // Add spacing before remove icon if needed
          IconButton(
            // Keep original remove row button
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: "Remove this document row",
            onPressed: () => setState(() => userDocuments.removeAt(index)),
          ),
        ],
      ),
    );
  }
} // End of _TenantProfilePageState

// ----------------- HOME RENTAL MODEL -----------------
class HomeRental {
  final String name;
  final String address;
  HomeRental({required this.name, required this.address});
}

class AnimatedGradientBackground extends StatefulWidget {
  const AnimatedGradientBackground({super.key});

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  final int _numberOfStars = 30; // Density
  late final List<_ShootingStar> _stars;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _stars = List.generate(
      _numberOfStars,
          (_) => _ShootingStar.random(_random),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final bgColor =
        Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
            const Color(0xFF01020A);

    return SizedBox.expand(
      child: Container(
        color: bgColor,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              size: Size(screenWidth, screenHeight),
              painter: _ShootingStarPainter(
                stars: _stars,
                progress: _controller.value,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// Shooting star model
class _ShootingStar {
  Offset start;
  Offset end;
  double size;
  double speed;

  _ShootingStar({
    required this.start,
    required this.end,
    required this.size,
    required this.speed,
  });

  factory _ShootingStar.random(Random random) {
    final startX = random.nextDouble();
    final startY = random.nextDouble();
    final endX =
        startX + (-0.2 + random.nextDouble() * 0.4); // horizontal variation
    final endY = startY + 0.2 + random.nextDouble() * 0.3; // downward movement

    return _ShootingStar(
      start: Offset(startX, startY),
      end: Offset(endX, endY),
      size: 1.5 + random.nextDouble() * 2.0,
      speed: 0.5 + random.nextDouble(),
    );
  }
}

// Painter
class _ShootingStarPainter extends CustomPainter {
  final List<_ShootingStar> stars;
  final double progress;
  final double screenWidth;
  final double screenHeight;

  _ShootingStarPainter({
    required this.stars,
    required this.progress,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;

    for (var star in stars) {
      final starProgress = (progress * star.speed) % 1.0;

      final x =
          lerpDouble(star.start.dx, star.end.dx, starProgress)! * screenWidth;
      final y =
          lerpDouble(star.start.dy, star.end.dy, starProgress)! * screenHeight;

      // Calculate movement direction vector
      final dx = star.end.dx - star.start.dx;
      final dy = star.end.dy - star.start.dy;
      final length = sqrt(dx * dx + dy * dy);
      final direction = Offset(dx / length, dy / length);

      // Trail opposite to movement
      final trailLength = star.size * 8; // visible length
      final trailEnd = Offset(
        x - direction.dx * trailLength * 10, // scaled for visible trail
        y - direction.dy * trailLength * 10,
      );

      final trailPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.6),
          ],
        ).createShader(Rect.fromPoints(trailEnd, Offset(x, y)))
        ..strokeWidth = star.size
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(trailEnd, Offset(x, y), trailPaint);

      // Draw star
      canvas.drawCircle(Offset(x, y), star.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShootingStarPainter oldDelegate) => true;
}






class RequestsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const RequestsPage2({super.key, required this.onBack});

  @override
  State<RequestsPage2> createState() => _RequestsPageState2();
}

class _RequestsPageState2 extends State<RequestsPage2> {
  final List<Map<String, String>> pendingRequests = [
    {"name": "John Doe", "property": "Sunset Apartments"},
    {"name": "Emma Wilson", "property": "Greenwood Villa"},
    {"name": "Michael Smith", "property": "Oceanview Residences"},
  ];

  final List<Map<String, String>> acceptedRequests = [];
  final List<Map<String, String>> rejectedRequests = [];

  void _handleAction(BuildContext context, Map<String, String> tenant, bool accept) async {
    final action = accept ? "accept" : "decline";

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        title: Text(
          "Confirm $action",
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          "Are you sure you want to $action ${tenant['name']}'s request?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              action.toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        pendingRequests.remove(tenant);
        if (accept) {
          acceptedRequests.add(tenant);
        } else {
          rejectedRequests.add(tenant);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background same as SearchPage
          const AnimatedGradientBackground(),

          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: "Requests",
                    onBack: widget.onBack,
                  ),

                  const Padding(
                    padding: EdgeInsets.only(top: 8.0, bottom: 10.0),
                    child: Center(
                      child: Text(
                        "Pending Requests",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // Pending Requests List with status only
                  ...pendingRequests.map(
                        (tenant) => Card(
                      color: Colors.white.withOpacity(0.1),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: Text(
                          tenant["name"]!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tenant["property"]!,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Status: Pending",
                              style: TextStyle(
                                color: Colors.amberAccent,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Tenantsearch_ProfilePage(
                                tenantName: tenant["name"]!,
                                propertyName: tenant["property"]!,
                                onBack: () => Navigator.pop(context),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Accepted Requests Section with status
                  if (acceptedRequests.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 20.0, bottom: 10),
                      child: Center(
                        child: Text(
                          "Approved Requests",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    ...acceptedRequests.map(
                          (tenant) => Card(
                        color: Colors.green.withOpacity(0.15),
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(
                            tenant["name"]!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tenant["property"]!,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "Status: Approved",
                                style: TextStyle(
                                  color: Colors.lightGreenAccent,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Rejected Requests Section with status
                  if (rejectedRequests.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 20.0, bottom: 10),
                      child: Center(
                        child: Text(
                          "Rejected Requests",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    ...rejectedRequests.map(
                          (tenant) => Card(
                        color: Colors.red.withOpacity(0.15),
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(
                            tenant["name"]!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tenant["property"]!,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "Status: Rejected",
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// -------------------- SEARCH PAGE --------------------
class SearchPage extends StatefulWidget {
  final VoidCallback onBack;
  const SearchPage({super.key, required this.onBack});

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  // --- MODIFIED: Removed "Location" controller ---
  final Map<String, TextEditingController> _filterControllers = {
    "Price": TextEditingController(),
    "People": TextEditingController(),
  };

  String? _activeFilter;
  bool _showResults = false;
  bool _isLoading = false; // Added loading state
  List<Map<String, dynamic>> _searchResults = []; // To store actual results

  // --- MODIFIED: Removed "Location" suggestions ---
  final Map<String, List<String>> filterSuggestions = {
    "Price": [
      "Below ₹5000",
      "₹5000 - ₹10000",
      "₹10000 - ₹20000",
      "Above ₹20000",
    ],
    "People": ["1 person", "2 people", "3 people", "4+ people"],
  };

  // Removed dummyResults

  // --- ADDED: Search Function ---
  Future<void> _performSearch() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _showResults = true; // Show results area (will show loading indicator)
      _searchResults = []; // Clear previous results
    });

    // --- MODIFIED: Check if filters are active ---
    final bool isFilterActive =
        _filterControllers["Price"]!.text.isNotEmpty ||
            _filterControllers["People"]!.text.isNotEmpty;

    // --- MODIFIED: Set searchTerm to empty if filters are active ---
    final String searchTerm = isFilterActive
        ? ""
        : _searchController.text.trim().toLowerCase();

    // --- REMOVED: locationFilter ---
    final String priceFilter = _filterControllers["Price"]!.text.trim();
    final String peopleFilter = _filterControllers["People"]!.text.trim();

    print(
      "Performing search with term: '$searchTerm', price: '$priceFilter', people: '$peopleFilter'",
    ); // Debug print

    try {
      // Base query for the 'house' collection
      QuerySnapshot houseSnapshot = await FirebaseFirestore.instance
          .collection('house')
          .get();
      List<Map<String, dynamic>> results = [];

      print(
        "Fetched ${houseSnapshot.docs.length} documents from 'house' collection.",
      ); // Debug print

      // --- Client-side Filtering ---
      for (var doc in houseSnapshot.docs) {
        String landlordUid = doc.id; // Landlord's UID is the document ID
        var houseData = doc.data() as Map<String, dynamic>?;

        if (houseData != null &&
            houseData.containsKey('properties') &&
            houseData['properties'] is List) {
          List<dynamic> properties = houseData['properties'];
          print(
            "Processing landlord $landlordUid with ${properties.length} properties.",
          ); // Debug print

          for (int i = 0; i < properties.length; i++) {
            var property = properties[i];
            if (property is Map<String, dynamic>) {
              // Extract data safely
              String location = (property['location'] as String? ?? '')
                  .toLowerCase();
              String rentStr = property['rent'] as String? ?? '';
              String occupancyStr = property['maxOccupancy'] as String? ?? '';
              String roomType = property['roomType'] as String? ?? '';

              // Apply Filters
              // --- REMOVED: locationMatch ---
              bool priceMatch =
                  priceFilter.isEmpty || _checkPriceMatch(rentStr, priceFilter);
              bool peopleMatch =
                  peopleFilter.isEmpty ||
                      _checkOccupancyMatch(occupancyStr, peopleFilter);

              // Apply Search Term (simple check against relevant fields)
              // If filters are active, searchTerm is "" so searchMatch is true
              bool searchMatch =
                  searchTerm.isEmpty ||
                      location.contains(searchTerm) ||
                      roomType.toLowerCase().contains(searchTerm) ||
                      rentStr.contains(searchTerm) ||
                      occupancyStr.toLowerCase().contains(searchTerm);

              print(
                "  Property $i: Loc='$location', Rent='$rentStr', Occ='$occupancyStr', Type='$roomType'",
              ); // Debug print
              print(
                "    Filters: PriceMatch=$priceMatch, PeopleMatch=$peopleMatch. SearchMatch=$searchMatch",
              ); // Debug print

              // --- MODIFIED: Removed locationMatch from check ---
              if (priceMatch && peopleMatch && searchMatch) {
                print(
                  "    MATCH FOUND for property $i of landlord $landlordUid.",
                ); // Debug print
                // Add relevant data for display and navigation
                results.add({
                  'landlordUid': landlordUid,
                  'propertyIndex': i, // Index within the properties array
                  'displayInfo':
                  '${roomType.isNotEmpty ? roomType : "Property"} - ${property['location'] ?? 'Unknown Location'}', // Example display
                  'propertyDetails': property, // Pass full property data
                });
              }
            } else {
              print("  Property $i data is not a Map."); // Debug print
            }
          }
        } else {
          print(
            "Landlord $landlordUid document data is invalid or missing 'properties' list.",
          ); // Debug print
        }
      }

      print(
        "Search complete. Found ${results.length} matching properties.",
      ); // Debug print

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error performing search: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching houses: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Helper function for Price Filter (Client-side) ---
  bool _checkPriceMatch(String rentStr, String priceFilter) {
    int? rent = int.tryParse(
      rentStr.replaceAll(RegExp(r'[^0-9]'), '').trim(),
    ); // Extract digits only
    if (rent == null) return false; // Cannot compare if rent is not a number

    switch (priceFilter) {
      case "Below ₹5000":
        return rent < 5000;
      case "₹5000 - ₹10000":
        return rent >= 5000 && rent <= 10000;
      case "₹10000 - ₹20000":
        return rent > 10000 && rent <= 20000; // Corrected lower bound
      case "Above ₹20000":
        return rent > 20000;
      default:
        return true; // No filter if category unknown
    }
  }

  // --- Helper function for People Filter (Client-side) ---
  bool _checkOccupancyMatch(String occupancyStr, String peopleFilter) {
    int? occupancy = int.tryParse(
      occupancyStr.replaceAll(RegExp(r'[^0-9]'), '').trim(),
    ); // Extract digits
    if (occupancy == null) return false;

    switch (peopleFilter) {
      case "1 person":
        return occupancy >= 1; // Allows 1 or more
      case "2 people":
        return occupancy >= 2;
      case "3 people":
        return occupancy >= 3;
      case "4+ people":
        return occupancy >= 4;
      default:
        return true; // No filter if category unknown
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- ADDED: Check if filters are active ---
    final bool isFilterActive =
        _filterControllers["Price"]!.text.isNotEmpty ||
            _filterControllers["People"]!.text.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: true, // Keep original
      body: Stack(
        children: [
          const AnimatedGradientBackground(), // Keep original
          SafeArea(
            child: Column(
              children: [
                // Make top content scrollable when keyboard opens
                Flexible(
                  // Keep Flexible for keyboard
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomTopNavBar(
                          // Keep original
                          showBack: true,
                          title: 'Search',
                          onBack: widget.onBack,
                        ),
                        const SizedBox(height: 10), // Keep spacing
                        Center(
                          // Keep original
                          child: Text(
                            "SEARCH HOMES",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18), // Keep spacing
                        // Filter buttons
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            // --- MODIFIED: Removed "Location" ---
                            children: ["Price", "People"].map((filter) {
                              bool isActive = _activeFilter == filter;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ElevatedButton.icon(
                                  icon: Icon(
                                    Icons.filter_alt,
                                    color: isActive
                                        ? Colors.black
                                        : Colors.white,
                                    size: 18,
                                  ),
                                  label: Text(
                                    filter,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isActive
                                        ? Colors.orange.shade300
                                        : Colors.white.withOpacity(
                                      0.15,
                                    ), // Highlight active
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _activeFilter = isActive ? null : filter;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // Active filter dropdown
                        if (_activeFilter != null)
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller:
                                  _filterControllers[_activeFilter!],
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText:
                                    "Enter ${_activeFilter!.toLowerCase()}...",
                                    hintStyle: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.08),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onSubmitted: (_) =>
                                      _performSearch(), // Optional: Search on submit from filter field
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: filterSuggestions[_activeFilter!]!
                                      .map(
                                        (option) => ChoiceChip(
                                      label: Text(option),
                                      labelStyle: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      backgroundColor: Colors.white
                                          .withOpacity(0.1),
                                      selectedColor: Colors.orange.shade700,
                                      selected:
                                      _filterControllers[_activeFilter!]!
                                          .text ==
                                          option,
                                      onSelected: (selected) {
                                        setState(() {
                                          _filterControllers[_activeFilter!]!
                                              .text = selected
                                              ? option
                                              : '';
                                          _activeFilter = null;
                                        });
                                        _performSearch(); // Trigger search immediately on filter selection
                                      },
                                    ),
                                  )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 20),

                        // --- MODIFIED: Hide Search bar if filters are active ---
                        if (!isFilterActive) ...[
                          // Search bar
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText:
                                    "Search homes, location, type...", // Updated hint
                                    hintStyle: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.08),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.3),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.orange.shade700,
                                      ),
                                    ), // Highlight border on focus
                                  ),
                                  onSubmitted: (_) =>
                                      _performSearch(), // Search when keyboard submit is pressed
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed:
                                _performSearch, // Call search function
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade700,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.search,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],

                        // --- END MODIFIED ---
                        const SizedBox(
                          height: 20,
                        ), // Add spacing before results might appear
                      ],
                    ),
                  ),
                ),

                // Search results Area
                if (_showResults)
                  Expanded(
                    child: _isLoading
                        ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.orange,
                      ),
                    ) // Show loading indicator
                        : (_searchResults.isEmpty
                        ? const Center(
                      child: Text(
                        "No homes found matching your criteria.",
                        style: TextStyle(color: Colors.white70),
                      ),
                    ) // Show no results message
                        : ListView.builder(
                      // Display actual results
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return GestureDetector(
                          // Keep original GestureDetector
                          onTap: () {
                            // --- Navigate with Landlord UID and Property Index/Details ---
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    Landlordsearch_ProfilePage(
                                      landlordUid:
                                      result['landlordUid'],
                                      propertyDetails:
                                      result['propertyDetails'], // Pass the specific property map
                                      propertyIndex:
                                      result['propertyIndex'], // Pass index for image path construction
                                    ),
                              ),
                            );
                          },
                          child: Container(
                            // Keep original result item style
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                            ),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(
                                10,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.home,
                                  color: Colors.orangeAccent,
                                ), // Keep icon
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    result['displayInfo'], // Use display info from result map
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white54,
                                ), // Add indicator for tap
                              ],
                            ),
                          ),
                        );
                      },
                    )),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} // End of _SearchPageState

// --- MODIFIED LANDLORD SEARCH PROFILE PAGE ---
// Needs to be StatefulWidget to fetch data
class Landlordsearch_ProfilePage extends StatefulWidget {
  final String landlordUid; // Landlord's UID from search
  final Map<String, dynamic> propertyDetails; // Specific property details
  final int propertyIndex; // Index of the property for image path

  const Landlordsearch_ProfilePage({
    super.key,
    required this.landlordUid,
    required this.propertyDetails,
    required this.propertyIndex,
  });

  @override
  _Landlordsearch_ProfilePageState createState() =>
      _Landlordsearch_ProfilePageState();
}

class _Landlordsearch_ProfilePageState
    extends State<Landlordsearch_ProfilePage> {
  String? _landlordName;
  String? _landlordPhoneNumber;
  String? _landlordEmail;
  String? _landlordProfilePicUrl;
  List<String> _propertyImageUrls = []; // To store fetched image URLs
  bool _isLoading = true; // Loading state

  // Dummy reviews remain the same
  final List<Map<String, dynamic>> dummyReviews = [
    {
      "name": "Anjali R.",
      "rating": 4,
      "comment":
      "Very responsive landlord! The flat was clean and matches the photos.",
      "date": "Oct 20, 2025",
    },
    {
      "name": "Rahul N.",
      "rating": 5,
      "comment":
      "Had a great experience. The location is perfect and rent is reasonable.",
      "date": "Sep 14, 2025",
    },
    {
      "name": "Sneha T.",
      "rating": 3,
      "comment":
      "Property is good but communication could be faster. Still recommended.",
      "date": "Aug 30, 2025",
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    // No need to set isLoading true here, already true initially
    // setState(() { _isLoading = true; });
    try {
      // 1. Fetch Landlord Details from 'landlord' collection
      print(
        "Fetching landlord details for UID: ${widget.landlordUid}",
      ); // Debug print
      DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(widget.landlordUid)
          .get();

      if (landlordDoc.exists && mounted) {
        var data = landlordDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          print("Landlord data found: $data"); // Debug print
          setState(() {
            _landlordName = data['fullName'] as String? ?? 'Name Not Available';
            _landlordPhoneNumber = data['phoneNumber'] as String?;
            _landlordEmail = data['email'] as String?;
            // Assuming profile pic URL isn't stored in landlord doc, fetch from storage next
          });
        } else {
          print("Landlord document data is null."); // Debug print
          if (mounted)
            setState(() => _landlordName = 'Landlord Data Not Found');
        }
      } else {
        print(
          "Landlord document not found for UID: ${widget.landlordUid}",
        ); // Debug print
        if (mounted) setState(() => _landlordName = 'Landlord Not Found');
      }

      // 2. Fetch Landlord Profile Pic from Storage
      print("Fetching landlord profile picture..."); // Debug print
      try {
        ListResult profilePicResult = await FirebaseStorage.instance
            .ref('${widget.landlordUid}/profile_pic/')
            .list(const ListOptions(maxResults: 1));
        if (profilePicResult.items.isNotEmpty && mounted) {
          String url = await profilePicResult.items.first.getDownloadURL();
          print("Profile picture URL fetched: $url"); // Debug print
          setState(() {
            _landlordProfilePicUrl = url;
          });
        } else {
          print("No profile picture found in storage."); // Debug print
        }
      } catch (storageError) {
        print(
          "Error fetching landlord profile pic: $storageError",
        ); // Keep default icon
      }

      // 3. Fetch Property Images from Storage
      List<String> imageUrls = [];
      String propertyFolderName =
          'property${widget.propertyIndex + 1}'; // property1, property2 etc.
      String imageFolderPath =
          '${widget.landlordUid}/$propertyFolderName/images/';
      print("Fetching property images from: $imageFolderPath"); // Debug print
      try {
        ListResult imageListResult = await FirebaseStorage.instance
            .ref(imageFolderPath)
            .listAll();
        print(
          "Found ${imageListResult.items.length} images in storage.",
        ); // Debug print
        for (var item in imageListResult.items) {
          String url = await item.getDownloadURL();
          imageUrls.add(url);
        }
        if (mounted) {
          print(
            "Setting ${imageUrls.length} property image URLs.",
          ); // Debug print
          setState(() {
            _propertyImageUrls = imageUrls;
          });
        }
      } catch (storageError) {
        print(
          "Error fetching property images from $imageFolderPath: $storageError",
        ); // Will show placeholders
      }
    } catch (e) {
      print("Error fetching landlord/property data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading details: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        print(
          "Finished fetching data, setting isLoading = false.",
        ); // Debug print
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- NO UI STRUCTURE CHANGES, only displaying fetched data ---
    return Scaffold(
      resizeToAvoidBottomInset: true, // Keep original
      body: Stack(
        children: [
          const AnimatedGradientBackground(), // Keep original
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTopNavBar(
                  // Keep original
                  showBack: true,
                  title: "Landlord Profile",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 20), // Keep spacing

                _isLoading
                    ? const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.orange,
                    ),
                  ),
                )
                    : Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ---------- Profile Header ----------
                        Center(
                          // Keep original structure
                          child: Column(
                            children: [
                              CircleAvatar(
                                // Display fetched or placeholder image
                                radius: 50,
                                backgroundColor: Colors.white.withOpacity(
                                  0.3,
                                ),
                                backgroundImage:
                                _landlordProfilePicUrl != null
                                    ? NetworkImage(
                                  _landlordProfilePicUrl!,
                                )
                                    : null,
                                child: _landlordProfilePicUrl == null
                                    ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 60,
                                )
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                // Display fetched name
                                _landlordName ??
                                    "...", // Show fetched name or placeholder
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                // Display fetched property location if available
                                widget.propertyDetails['location'] ??
                                    "Location Unknown", // Fetch from passed details
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25), // Keep spacing
                        // ---------- Send Request Button (Keep original) ----------
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Request sent to the landlord!',
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              // Add actual request sending logic here if needed
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade700,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.send,
                              color: Colors.white,
                            ),
                            label: const Text(
                              "Send Request",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 25), // Keep spacing
                        // ---------- Property Photos ----------
                        const Text(
                          "Property Photos",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ), // Keep style
                        const SizedBox(height: 10), // Keep spacing
                        SizedBox(
                          height: 140,
                          child:
                          _propertyImageUrls
                              .isEmpty // Check if images were fetched
                              ? Container(
                            // Show placeholder if no images or still loading
                            width: double
                                .infinity, // Take available width
                            margin: const EdgeInsets.only(
                              right: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(
                                12,
                              ),
                            ),
                            child: Center(
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                color: Colors.white54,
                              )
                                  : const Icon(
                                Icons.hide_image_outlined,
                                color: Colors.white70,
                                size: 40,
                              ),
                            ),
                          )
                              : ListView.builder(
                            // Use ListView.builder for fetched images
                            scrollDirection: Axis.horizontal,
                            itemCount: _propertyImageUrls.length,
                            itemBuilder: (context, index) {
                              return Container(
                                width: 160,
                                margin: const EdgeInsets.only(
                                  right: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(
                                    0.2,
                                  ), // Background while loading
                                  borderRadius:
                                  BorderRadius.circular(12),
                                  image: DecorationImage(
                                    image: NetworkImage(
                                      _propertyImageUrls[index],
                                    ), // Use NetworkImage
                                    fit: BoxFit.cover,
                                    // Optional: Add error builder for NetworkImage
                                    onError: (exception, stackTrace) {
                                      print(
                                        "Error loading image URL ${_propertyImageUrls[index]}: $exception",
                                      );
                                      // Optionally return a placeholder widget here too
                                    },
                                  ),
                                ),
                                // Removed overlay icon from original example
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 30), // Keep spacing
                        // ---------- About Property (Display fetched data) ----------
                        _infoContainer("About Property", [
                          _infoRow(
                            Icons.home,
                            widget.propertyDetails['roomType'] ?? 'N/A',
                          ),
                          _infoRow(
                            Icons.location_on,
                            widget.propertyDetails['location'] ?? 'N/A',
                          ),
                          _infoRow(
                            Icons.attach_money,
                            "₹${widget.propertyDetails['rent'] ?? 'N/A'} / month",
                          ),
                          _infoRow(
                            Icons.people,
                            "Max Occupancy: ${widget.propertyDetails['maxOccupancy'] ?? 'N/A'}",
                          ), // Slightly clearer text
                        ]),
                        const SizedBox(height: 25), // Keep spacing
                        // ---------- Contact Section (Display fetched data) ----------
                        _infoContainer("Contact Details", [
                          _infoRow(
                            Icons.phone,
                            _landlordPhoneNumber ?? 'Not Available',
                          ),
                          _infoRow(
                            Icons.email,
                            _landlordEmail ?? 'Not Available',
                          ),
                        ]),
                        const SizedBox(height: 25), // Keep spacing
                        // ---------- Write a Review Button (Keep original) ----------
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () => _showReviewDialog(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade700,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.reviews,
                              color: Colors.white,
                            ),
                            label: const Text(
                              "Write a Review",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 35), // Keep spacing
                        // ---------- Reviews Section (Keep original dummy data) ----------
                        const Text(
                          "Reviews",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ), // Keep style
                        const SizedBox(height: 10), // Keep spacing
                        ...dummyReviews.map((review) {
                          // Keep original review display structure
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              // Keep original review content structure
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.orange
                                          .withOpacity(0.8),
                                      child: Text(
                                        review['name'][0],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          review['name'],
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Row(
                                          children: List.generate(
                                            5,
                                                (index) => Icon(
                                              index < review['rating']
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              size: 18,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      review['date'],
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  review['comment'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 40), // Keep spacing
                      ],
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

  // ---------- Helper Widgets (Keep Original) ----------
  static Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.orangeAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _infoContainer(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  // --- Review Dialog (Keep Original Dummy Logic) ---
  void _showReviewDialog(BuildContext context) {
    final TextEditingController reviewController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Use dialogContext
        backgroundColor: Colors.black87, // Keep style
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ), // Keep style
        title: const Text(
          "Write a Review",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ), // Keep style
        content: TextField(
          // Keep style
          controller: reviewController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Enter your review here...",
            hintStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          // Keep style
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Use dialogContext
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Review submitted: ${reviewController.text}"),
                ),
              ); // Keep logic
              // Add actual review saving logic here
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: const Text("Submit", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
} // End of _Landlordsearch_ProfilePageState

// -------------------- SETTINGS PAGE --------------------
class SettingsPage2 extends StatelessWidget {
  final VoidCallback onBack;
  const SettingsPage2({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> _settingsOptions = [
      {
        'title': 'Edit Profile',
        'icon': Icons.person_outline,
        'color': Colors.blue,
        'action': (BuildContext context) => _showEditProfileDialog(context),
      },
      {
        'title': 'Change Password',
        'icon': Icons.lock_outline,
        'color': Colors.orange,
        'action': (BuildContext context) => _showChangePasswordDialog(context),
      },
      {
        'title': 'Notification Preferences',
        'icon': Icons.notifications_none,
        'color': Colors.green,
        'action': (BuildContext context) => print('Navigate to Notifications'),
      },
      {
        'title': 'Privacy & Security',
        'icon': Icons.security,
        'color': Colors.purple,
        'action': (BuildContext context) => print('Navigate to Privacy'),
      },
      {
        'title': 'Help & Support',
        'icon': Icons.help_outline,
        'color': Colors.yellow.shade700,
        'action': (BuildContext context) => _showHelpDialog(context),
      },
    ];

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "Settings",
                  onBack: onBack,
                ),
                const SizedBox(height: 20),

                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Account Settings",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        ..._settingsOptions.map((option) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassmorphismContainer(
                              borderRadius: 15,
                              opacity: 0.08,
                              onTap: () => option['action'](context),
                              child: Row(
                                children: [
                                  Icon(
                                    option['icon'],
                                    color: option['color'],
                                    size: 30,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Text(
                                      option['title'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white54,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),

                        const SizedBox(height: 30),

                        // -------------------- LOGOUT BUTTON --------------------
                        GlassmorphismContainer(
                          borderRadius: 15,
                          opacity: 0.08,
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) =>
                                  AlertDialog(
                                    backgroundColor: const Color(0xFF1E2A47),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    title: const Text(
                                      "Confirm Logout",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: const Text(
                                      "Are you sure you want to logout?",
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text(
                                          "Cancel",
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                        ),
                                        onPressed: () {
                                          Navigator.pop(dialogContext);
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const LoginPage(),
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          "Logout",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.logout,
                                color: Colors.redAccent,
                                size: 30,
                              ),
                              SizedBox(width: 15),
                              Text(
                                'LOGOUT',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
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

  // ---------------------- HELP & SUPPORT DIALOG ----------------------
  static void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Help & Support",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Contact Admin:\n\n📞 +91 9497320928 \n\n📞 +91 8281258530",
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Close",
              style: TextStyle(color: Colors.blueAccent),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------- EDIT PROFILE DIALOG ----------------------
  // --- UPDATED EDIT PROFILE DIALOG ---
  // IMPORTANT: Assumes necessary imports exist at the top of the file:
  // import 'dart:io';
  // import 'package:flutter/material.dart';
  // import 'package:image_picker/image_picker.dart';
  // import 'package:firebase_auth/firebase_auth.dart';
  // import 'package:cloud_firestore/cloud_firestore.dart';
  // import 'package:firebase_storage/firebase_storage.dart';
  // import 'package:email_validator/email_validator.dart'; // Needed if _buildInputField is reused by password dialog

  static void _showEditProfileDialog(BuildContext context) {
    // Keep controllers for fields being edited
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController =
    TextEditingController(); // Represents profileName (UserId)
    final TextEditingController phoneController = TextEditingController();
    // Removed email and address controllers

    // Variables for image picking and loading state need to be managed within StatefulBuilder
    XFile? _pickedImageFile;
    bool _isUpdating = false;

    // --- Pre-fetch current data (Cannot be done easily in static function without passing data) ---
    // --- User will have to re-type existing values or logic needs adjustment ---

    showDialog(
      context: context,
      // Use StatefulBuilder to manage the state within the dialog
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, stfSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47), // Keep original color
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ), // Keep shape
            title: const Text(
              // Keep title style
              "Edit Profile",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      // --- Image Picking Logic ---
                      if (_isUpdating) return;
                      final ImagePicker picker = ImagePicker();
                      try {
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          stfSetState(() {
                            // Use StatefulBuilder's setState
                            _pickedImageFile = image;
                          });
                          print("Image picked: ${image.path}");
                        } else {
                          print("Image picking cancelled.");
                        }
                      } catch (e) {
                        print("Error picking image: $e");
                        // Show error Snackbar using the original context
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to pick image'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: CircleAvatar(
                      // Keep original CircleAvatar structure
                      radius: 40,
                      backgroundColor:
                      Colors.grey.shade700, // Keep placeholder background
                      backgroundImage: _pickedImageFile != null
                          ? FileImage(
                        File(_pickedImageFile!.path),
                      ) // Show picked file
                      // --- TODO: Fetch and display current image here if desired, requires passing URL or fetching ---
                          : const AssetImage('assets/profile_placeholder.png')
                      as ImageProvider, // Keep placeholder
                      child: const Align(
                        // Keep edit icon overlay
                        alignment: Alignment.bottomRight,
                        child: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          radius: 14,
                          child: Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15), // Keep spacing
                  // Use provided _buildInputField
                  _buildInputField(nameController, "Full Name"),
                  _buildInputField(
                    idController,
                    "User ID",
                  ), // Profile Name (UserId)
                  _buildInputField(phoneController, "Phone Number"),
                  // Email and Address fields removed as requested
                ],
              ),
            ),
            actions: [
              // Keep original actions structure
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext), // Use dialogContext
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ), // Keep style
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Keep color
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: _isUpdating
                    ? null
                    : () async {
                  // --- UPDATE LOGIC ---
                  stfSetState(() {
                    _isUpdating = true;
                  });
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(dialogContext);

                  final String? uid =
                      FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Error Not logged in'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isUpdating = false;
                    });
                    return;
                  }

                  try {
                    //String? imageUrl; // Only used locally if needed later

                    // 1. Upload Image if picked
                    if (_pickedImageFile != null) {
                      print("Uploading profile picture...");
                      // Path: uid/profile_pic/profile_image.jpg (overwrites previous)
                      String filePath =
                          '$uid/profile_pic/profile_image.jpg';
                      Reference storageRef = FirebaseStorage.instance
                          .ref()
                          .child(filePath);
                      UploadTask uploadTask = storageRef.putFile(
                        File(_pickedImageFile!.path),
                      );
                      await uploadTask; // Wait for upload to complete
                      print("Profile picture uploaded successfully.");
                      // imageUrl = await snapshot.ref.getDownloadURL(); // Get URL only if needed
                    }

                    // 2. Prepare data for Firestore update
                    final String newFullName = nameController.text.trim();
                    final String newProfileName = idController.text
                        .trim(); // User ID field is Profile Name
                    final String newPhoneNumber = phoneController.text
                        .trim();

                    Map<String, dynamic> updateData = {};
                    if (newFullName.isNotEmpty)
                      updateData['fullName'] = newFullName;
                    if (newProfileName.isNotEmpty)
                      updateData['profileName'] = newProfileName;
                    if (newPhoneNumber.isNotEmpty)
                      updateData['phoneNumber'] = newPhoneNumber;

                    // 3. Update Firestore if there's data to update
                    if (updateData.isNotEmpty) {
                      print(
                        "Updating Firestore (tenant collection) for UID: $uid with data: $updateData",
                      );
                      // --- UPDATED: Use 'tenant' collection ---
                      await FirebaseFirestore.instance
                          .collection('tenant')
                          .doc(uid)
                          .update(updateData);
                      print("Firestore update successful.");

                      // 4. Update unique UserId collection IF profileName changed
                      // Warning: This only adds, doesn't check uniqueness thoroughly again or remove old.
                      if (newProfileName.isNotEmpty) {
                        // Optional: Re-check uniqueness before adding for robustness
                        final checkSnap = await FirebaseFirestore.instance
                            .collection('UserIds')
                            .where('UserId', isEqualTo: newProfileName)
                            .limit(1)
                            .get();
                        if (checkSnap.docs.isEmpty) {
                          print(
                            "Adding new unique profile name to UserIds collection.",
                          );
                          await FirebaseFirestore.instance
                              .collection('UserIds')
                              .add({'UserId': newProfileName});
                          // Note: Does not remove the old profile name.
                        } else {
                          print(
                            "New profile name might already exist (race condition/old data?). Not adding again.",
                          );
                          // Decide handling: ignore (current), or throw error?
                          // throw Exception('Profile name already exists');
                        }
                      }
                    } else if (_pickedImageFile != null) {
                      print(
                        "Only profile picture was updated, skipping Firestore field update.",
                      );
                    } else {
                      print(
                        "No fields changed and no new picture, skipping updates.",
                      );
                    }

                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    navigator.pop(); // Close dialog on success
                  } catch (e) {
                    print("Error updating profile: $e");
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Update failed ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    // Keep dialog open on error
                  } finally {
                    // Ensure loading state is reset
                    if (navigator.context.mounted) {
                      stfSetState(() {
                        _isUpdating = false;
                      });
                    }
                  }
                },
                child:
                _isUpdating // Show loading indicator or text
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  "Update",
                  style: TextStyle(color: Colors.white),
                ), // Keep style
              ),
            ],
          );
        },
      ),
    );
  }

  // --- UPDATED CHANGE PASSWORD DIALOG ---
  static void _showChangePasswordDialog(BuildContext context) {
    // Removed oldPassController
    final TextEditingController newPassController = TextEditingController();
    final TextEditingController confirmPassController = TextEditingController();
    bool _isChangingPassword = false; // Loading state

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        // Use StatefulBuilder for loading state
        builder: (stfContext, stfSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47), // Keep style
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ), // Keep style
            title: const Text(
              // Keep style
              "Change Password",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Removed old password field
                  _buildInputField(
                    newPassController,
                    "New Password",
                    isPassword: true,
                  ),
                  _buildInputField(
                    confirmPassController,
                    "Confirm Password",
                    isPassword: true,
                  ),
                ],
              ),
            ),
            actions: [
              // Keep style
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent, // Keep style
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: _isChangingPassword
                    ? null
                    : () async {
                  // --- Simplified Password Change Logic ---
                  stfSetState(() {
                    _isChangingPassword = true;
                  });
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(dialogContext);

                  final String newPassword =
                      newPassController.text; // No trim
                  final String confirmPassword =
                      confirmPassController.text; // No trim

                  // Validation
                  if (newPassword.isEmpty || confirmPassword.isEmpty) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Please fill both password fields'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }
                  if (newPassword != confirmPassword) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('New passwords do not match'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }
                  // Password complexity rules (assuming same as registration)
                  if (newPassword.length < 6) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'New password must be at least 6 characters long',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }
                  if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(newPassword)) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'New password must contain only letters and numbers',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }

                  User? user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    // Check user directly
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Error Not logged in'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    stfSetState(() {
                      _isChangingPassword = false;
                    });
                    return;
                  }

                  try {
                    // Directly update password (no re-authentication)
                    print("Attempting to update password directly...");
                    await user.updatePassword(newPassword);
                    print(
                      "Password updated successfully via direct method!",
                    );

                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Password changed successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    navigator.pop(); // Close dialog on success
                  } on FirebaseAuthException catch (e) {
                    print(
                      "Error changing password directly: ${e.code} - ${e.message}",
                    );
                    String errorMsg =
                        'Failed to change password Please try again'; // Default
                    // Handle common errors from direct update
                    if (e.code == 'weak-password') {
                      errorMsg = 'New password is too weak';
                    } else if (e.code == 'requires-recent-login') {
                      // This error CAN still happen even without explicitly asking for re-auth
                      errorMsg =
                      'This action requires recent login Please log out and log in again';
                    } else {
                      errorMsg = 'Error ${e.message ?? e.code}';
                    }
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(errorMsg),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } catch (e) {
                    print("Generic error changing password: $e");
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to change password ${e.toString()}',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } finally {
                    if (navigator.context.mounted) {
                      stfSetState(() {
                        _isChangingPassword = false;
                      });
                    }
                  }
                },
                child:
                _isChangingPassword // Show loading or text
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  "Update",
                  style: TextStyle(color: Colors.white),
                ), // Keep style
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Provided _buildInputField ---
  // Assuming this is defined statically within the same class or globally accessible
  static Widget _buildInputField(
      TextEditingController controller,
      String hint, {
        bool isPassword = false,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// -------------------- AGREEMENTS PAGE --------------------
class AgreementsPage2 extends StatelessWidget {
  final VoidCallback onBack;
  const AgreementsPage2({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "Agreements",
                  onBack: onBack,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Agreements List",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
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

// -------------------- PAYMENTS PAGE --------------------
class PaymentsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage2({super.key, required this.onBack});

  @override
  State<PaymentsPage2> createState() => _PaymentsPage2State();
}

class _PaymentsPage2State extends State<PaymentsPage2> {
  String? selectedMethod;
  final TextEditingController _amountController = TextEditingController();

  // Mock transactions
  final List<Map<String, dynamic>> mockTransactions = [
    {
      'amount': 499,
      'method': 'UPI',
      'date': '18 Oct 2025, 10:45 AM',
      'status': 'Success',
    },
    {
      'amount': 799,
      'method': 'Credit Card',
      'date': '15 Oct 2025, 2:22 PM',
      'status': 'Pending',
    },
    {
      'amount': 299,
      'method': 'Net Banking',
      'date': '10 Oct 2025, 9:10 PM',
      'status': 'Success',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---------- TOP NAV BAR ----------
                CustomTopNavBar(
                  showBack: true,
                  title: "Payments",
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 15),

                // ---------- SCROLLABLE CONTENT ----------
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // -------------------- PAYMENT SETUP --------------------
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Make a Payment",
                                  style: TextStyle(
                                    color: Colors.orange.shade300,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "Choose your payment method (India):",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Payment method buttons
                                Wrap(
                                  spacing: 10,
                                  children: [
                                    _paymentButton(
                                      "UPI",
                                      Icons.account_balance_wallet,
                                    ),
                                    _paymentButton(
                                      "Credit/Debit Card",
                                      Icons.credit_card,
                                    ),
                                    _paymentButton(
                                      "Net Banking",
                                      Icons.account_balance,
                                    ),
                                    _paymentButton("Wallets", Icons.wallet),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Dynamic payment fields
                                if (selectedMethod != null)
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: _buildPaymentFields(selectedMethod!),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),
                        // -------------------- TRANSACTION HISTORY --------------------
                        Text(
                          "Transaction History",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: mockTransactions.length,
                          itemBuilder: (context, index) {
                            var data = mockTransactions[index];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.2),
                                    ),
                                  ),
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.receipt_long,
                                      color: Colors.orange.shade400,
                                    ),
                                    title: Text(
                                      "₹${data['amount']} - ${data['method']}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      data['date'],
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                    ),
                                    trailing: Text(
                                      data['status'],
                                      style: TextStyle(
                                        color: data['status'] == "Success"
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 60),
                      ],
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

  // -------------------- PAYMENT BUTTON --------------------
  Widget _paymentButton(String title, IconData icon) {
    final bool isSelected = selectedMethod == title;
    return ElevatedButton.icon(
      onPressed: () => setState(() => selectedMethod = title),
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(title, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Colors.orange.shade700
            : Colors.white.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // -------------------- PAYMENT FIELDS --------------------
  Widget _buildPaymentFields(String method) {
    switch (method) {
      case "UPI":
        return Column(
          key: const ValueKey("UPI"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Enter UPI ID (e.g. name@okaxis)"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Credit/Debit Card":
        return Column(
          key: const ValueKey("Card"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Card Number"),
            const SizedBox(height: 10),
            _textField("Card Holder Name"),
            const SizedBox(height: 10),
            _textField("Expiry (MM/YY)"),
            const SizedBox(height: 10),
            _textField("CVV", obscure: true),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Net Banking":
        return Column(
          key: const ValueKey("NetBanking"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Bank Name"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Wallets":
        return Column(
          key: const ValueKey("Wallets"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Wallet Name (Paytm, PhonePe, etc.)"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // -------------------- SHARED INPUTS --------------------
  Widget _textField(String hint, {bool obscure = false}) {
    return TextField(
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
      ),
    );
  }

  Widget _amountField() {
    return TextField(
      controller: _amountController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Enter Amount (₹)",
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
      ),
    );
  }

  Widget _proceedButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: ElevatedButton(
        onPressed: () {
          String amount = _amountController.text.trim();
          if (amount.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please enter an amount")),
            );
            return;
          }

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E2A47),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text(
                "Confirm Payment",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                "Are you sure you want to proceed with ₹$amount via $selectedMethod?",
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Payment of ₹$amount initiated via $selectedMethod",
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    "Confirm",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Center(
          child: Text(
            "Proceed to Pay",
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class Tenantsearch_ProfilePage extends StatelessWidget {
  final String tenantName;
  final String propertyName;
  final VoidCallback onBack;

  const Tenantsearch_ProfilePage({
    super.key,
    required this.tenantName,
    required this.propertyName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final dummyReviews = [
      {"reviewer": "Landlord A", "comment": "Great tenant, pays on time!"},
      {"reviewer": "Landlord B", "comment": "Clean and respectful."},
    ];

    final tenantRequirements = [
      "1 BHK apartment",
      "Budget: \$1200/month",
      "Prefers furnished",
      "Pet-friendly",
    ];

    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),

          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: "Tenant Profile",
                    onBack: onBack,
                  ),
                  const SizedBox(height: 16),

                  // Tenant Avatar + Info
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white24,
                    child: Text(
                      tenantName[0],
                      style: const TextStyle(fontSize: 40, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tenantName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Interested in $propertyName",
                    style: const TextStyle(color: Colors.white70),
                  ),

                  const SizedBox(height: 20),

                  // Requirements Section
                  const Text(
                    "Requirements",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...tenantRequirements.map(
                        (req) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        req,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Reviews Section
                  const Text(
                    "Reviews",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...dummyReviews.map(
                        (r) => Card(
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text(
                          r["reviewer"]!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          r["comment"]!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Review Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    onPressed: () {
                      // TODO: Add review popup or form
                    },
                    child: const Text("Review"),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
