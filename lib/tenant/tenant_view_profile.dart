import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';

class TenantsearchProfilePage2 extends StatefulWidget {
  final VoidCallback onBack;

  const TenantsearchProfilePage2({super.key, required this.onBack});

  @override
  State<TenantsearchProfilePage2> createState() =>
      _TenantsearchProfilePage2State();
}

class _TenantsearchProfilePage2State extends State<TenantsearchProfilePage2> {
  String? _tenantName;
  String? _profilePicUrl;
  bool _isLoadingProfile = true;
  bool _isAadharVerified = false; // New state for Aadhaar verification

  late final String _tenantUid;

  @override
  void initState() {
    super.initState();

    // Assigning the global uid variable (as it was in your original code)
    _tenantUid = uid;

    _fetchTenantData();
  }

  // ---------------- FETCH TENANT DATA ----------------
  Future<void> _fetchTenantData() async {
    try {
      // 1. Fetch Tenant Document from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('tenant')
          .doc(_tenantUid)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _tenantName = data['fullName'];
          // Safely check if the 'aadhar' field exists and equals 'verified'
          _isAadharVerified = data['aadhar'] == 'verified';
        });
      }
    } catch (e) {
      debugPrint("Error fetching tenant data: $e");
    }

    try {
      // 2. Fetch Profile Picture from Firebase Storage
      final result = await FirebaseStorage.instance
          .ref('$_tenantUid/profile_pic/')
          .list(const ListOptions(maxResults: 1));

      if (result.items.isNotEmpty) {
        final url = await result.items.first.getDownloadURL();
        if (mounted) {
          setState(() {
            _profilePicUrl = url;
          });
        }
      }
    } catch (e) {
      debugPrint("No profile picture found");
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, // Disable automatic system pop
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        // Manually go back to the previous page
        Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            const AnimatedGradientBackground(),
            SafeArea(
              child: Column(
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: "Tenant Profile",
                    onBack: widget.onBack,
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start, // Aligns text to the left
                        children: [
                          // -------- PROFILE ----------
                          Center(
                            child: CircleAvatar(
                              radius: 55,
                              backgroundColor: Colors.white12,
                              backgroundImage: _profilePicUrl != null
                                  ? NetworkImage(_profilePicUrl!)
                                  : null,
                              child: _isLoadingProfile
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : (_profilePicUrl == null
                                        ? const Icon(
                                            Icons.person,
                                            size: 60,
                                            color: Colors.white,
                                          )
                                        : null),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Center(
                            child: Text(
                              _tenantName ?? "Tenant",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),

                          // -------- ID PROOF SECTION ----------
                          Text(
                            "ID Proof",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),

                          _isLoadingProfile
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : _isAadharVerified
                              ? GlassmorphismContainer(
                                  opacity: 0.1,
                                  child: const ListTile(
                                    leading: Icon(
                                      Icons.verified_user,
                                      color: Colors.green,
                                      size: 30,
                                    ),
                                    title: Text(
                                      "Aadhaar",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: Text(
                                      "DigiLocker verified",
                                      style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    trailing: Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    ),
                                  ),
                                )
                              : const Padding(
                                  padding: EdgeInsets.only(left: 4.0),
                                  child: Text(
                                    "No verified ID proof available.",
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),

                          const SizedBox(height: 40),
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
}
