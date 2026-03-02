import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:email_validator/email_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

      // SINGLE LOGIN LOGIC USING FIREBASE AUTH
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
          if (data != null && data.containsKey('role') && data['role'] is int) {
            userRole = data['role'] as int?;
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
    TextEditingController resetEmailController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141E30),
              title: const Text(
                'Reset Password',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter your registered email address:',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: resetEmailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Email",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                  onPressed: _isSendingResetEmail
                      ? null
                      : () async {
                          final String enteredEmail = resetEmailController.text
                              .trim();
                          final scaffoldMessenger = ScaffoldMessenger.of(
                            context,
                          );

                          if (enteredEmail.isEmpty ||
                              !EmailValidator.validate(enteredEmail)) {
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid email'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          setStateDialog(() {
                            _isSendingResetEmail = true;
                          });

                          try {
                            // Check if email exists in 'email' collection
                            final querySnapshot = await FirebaseFirestore
                                .instance
                                .collection('email')
                                .where('email', isEqualTo: enteredEmail)
                                .limit(1)
                                .get();

                            if (querySnapshot.docs.isNotEmpty) {
                              // Email exists, send reset email
                              await FirebaseAuth.instance
                                  .sendPasswordResetEmail(email: enteredEmail);

                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Password reset email sent to $enteredEmail',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              if (context.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                            } else {
                              // Email does not exist
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Account doesn\'t exist'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            if (context.mounted) {
                              setStateDialog(() {
                                _isSendingResetEmail = false;
                              });
                            }
                          }
                        },
                  child: _isSendingResetEmail
                      ? const SizedBox(
                          height: 15,
                          width: 15,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Send',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // Reset state when dialog is closed
      if (mounted) {
        setState(() {
          _isSendingResetEmail = false;
        });
      }
    });
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
                onPressed: _forgotPassword,
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
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
