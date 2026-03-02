import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:main_project/config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class TenantProfilePage extends StatefulWidget {
  final VoidCallback onBack;

  const TenantProfilePage({super.key, required this.onBack});

  @override
  TenantProfilePageState createState() => TenantProfilePageState();
}

// CHANGED: Added AutomaticKeepAliveClientMixin to preserve state during navigation
class TenantProfilePageState extends State<TenantProfilePage>
    with AutomaticKeepAliveClientMixin<TenantProfilePage> {
  // CHANGED: Ensure state is kept alive
  @override
  bool get wantKeepAlive => true;

  // --- State variables for fetched data ---
  String? _tenantName;
  String? _profilePicUrl;
  bool _isLoadingProfile = true;

  // --- NEW: Aadhar Verification State ---
  bool _isAadharVerified = false;

  // --- Rented Homes ---
  List<Map<String, dynamic>> _rentedHomes = [];
  bool _isLoadingHomes = true;

  @override
  void initState() {
    super.initState();
    _fetchTenantData();
    _fetchRentedHomes();
    saveDeviceToken();
  }

  Future<void> _fetchTenantData() async {
    // 1. SDK LOGIC (Android/iOS)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        DocumentSnapshot tenantDoc = await FirebaseFirestore.instance
            .collection('tenant')
            .doc(uid)
            .get();
        if (tenantDoc.exists && mounted) {
          var data = tenantDoc.data() as Map<String, dynamic>?;
          if (data != null) {
            setState(() {
              if (data.containsKey('fullName')) {
                _tenantName = data['fullName'] as String?;
              }
              if (data.containsKey('aadhar')) {
                _isAadharVerified = data['aadhar'] == 'verified';
              }
            });
          }
        }
        ListResult result = await FirebaseStorage.instance
            .ref('$uid/profile_pic/')
            .list(const ListOptions(maxResults: 1));
        if (result.items.isNotEmpty && mounted) {
          String url = await result.items.first.getDownloadURL();
          setState(() => _profilePicUrl = url);
        }
      } catch (e) {
        // Ignore errors
      } finally {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    }
    // 2. REST LOGIC (Web/Desktop)
    else {
      try {
        final tenantUrl = Uri.parse(
          '$kFirestoreBaseUrl/tenant/$uid?key=$kFirebaseAPIKey',
        );
        final tenantRes = await http.get(tenantUrl);
        if (tenantRes.statusCode == 200) {
          final data = jsonDecode(tenantRes.body);
          if (data['fields'] != null) {
            setState(() {
              if (data['fields']['fullName'] != null) {
                _tenantName = data['fields']['fullName']['stringValue'];
              }
              if (data['fields']['aadhar'] != null) {
                _isAadharVerified =
                    data['fields']['aadhar']['stringValue'] == 'verified';
              }
            });
          }
        }

        final picUrl = Uri.parse(
          '$kStorageBaseUrl?prefix=$uid/profile_pic/&key=$kFirebaseAPIKey',
        );
        final picRes = await http.get(picUrl);
        if (picRes.statusCode == 200) {
          final data = jsonDecode(picRes.body);
          if (data['items'] != null && (data['items'] as List).isNotEmpty) {
            String objectName = data['items'][0]['name'];
            String encodedName = Uri.encodeComponent(objectName);
            String url =
                '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
            if (mounted) setState(() => _profilePicUrl = url);
          }
        }
      } catch (e) {
        // Ignore
      } finally {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    }
  }

  Future<void> _fetchRentedHomes() async {
    // 1. SDK LOGIC
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('tagreements')
            .doc(uid)
            .get();

        if (doc.exists && mounted) {
          Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('agreements')) {
            List<dynamic> allAgreements = data['agreements'];
            List<Map<String, dynamic>> parsedAgreements = allAgreements
                .map((req) => req as Map<String, dynamic>)
                .toList();

            setState(() {
              _rentedHomes = parsedAgreements;
              _isLoadingHomes = false;
            });
          } else {
            if (mounted) setState(() => _isLoadingHomes = false);
          }
        } else {
          if (mounted) setState(() => _isLoadingHomes = false);
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingHomes = false);
      }
    }
    // 2. REST LOGIC
    else {
      try {
        final url = Uri.parse(
          '$kFirestoreBaseUrl/tagreements/$uid?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null && data['fields']['agreements'] != null) {
            var rawList =
                data['fields']['agreements']['arrayValue']['values'] as List?;
            if (rawList != null) {
              List<Map<String, dynamic>> parsedAgreements = [];
              for (var item in rawList) {
                if (item['mapValue'] != null &&
                    item['mapValue']['fields'] != null) {
                  Map<String, dynamic> cleanMap = {};
                  item['mapValue']['fields'].forEach((key, val) {
                    cleanMap[key] = parseFirestoreRestValue(val);
                  });
                  parsedAgreements.add(cleanMap);
                }
              }
              if (mounted) {
                setState(() {
                  _rentedHomes = parsedAgreements;
                  _isLoadingHomes = false;
                });
                return;
              }
            }
          }
        }
        if (mounted) setState(() => _isLoadingHomes = false);
      } catch (e) {
        if (mounted) setState(() => _isLoadingHomes = false);
      }
    }
  }

  // --- NEW: Mock DigiLocker Verification Logic ---
  Future<void> _verifyAadharWithDigiLocker() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MockDigiLockerGateway(
        onSuccess: () async {
          // 1. Show processing dialog while updating Firestore
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (c) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              content: Row(
                children: const [
                  CircularProgressIndicator(color: Colors.blueAccent),
                  SizedBox(width: 20),
                  Text(
                    "Updating Profile...",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );

          try {
            final String userUid = uid;

            // 2. Save to Firestore
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              await FirebaseFirestore.instance
                  .collection('tenant')
                  .doc(userUid)
                  .update({'aadhar': 'verified'});
            } else {
              final url = Uri.parse(
                '$kFirestoreBaseUrl/tenant/$userUid?updateMask.fieldPaths=aadhar&key=$kFirebaseAPIKey',
              );
              String? token = await FirebaseAuth.instance.currentUser
                  ?.getIdToken();
              await http.patch(
                url,
                body: jsonEncode({
                  "fields": {
                    "aadhar": {"stringValue": "verified"},
                  },
                }),
                headers: {
                  "Content-Type": "application/json",
                  "Authorization": "Bearer $token",
                },
              );
            }

            // 3. Success UI
            if (mounted) {
              Navigator.pop(context); // Close loading dialog
              setState(() {
                _isAadharVerified = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Aadhaar Verified Successfully!"),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            // 4. Error UI
            if (mounted) {
              Navigator.pop(context); // Close loading dialog
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Verification Failed: $e"),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  // --- NEW: Apartment Details Popup & Review Logic ---
  void _showApartmentDetailsPopup(Map<String, dynamic> req) {
    final String name = req['apartmentName'] ?? "Rented Property";
    final String landlord = req['landlordName'] ?? "Unknown Landlord";
    final String location = req['panchayat'] ?? "Unknown Location";
    final String landlordUid = req['landlordUid'] ?? "";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Location: $location",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Landlord: $landlord",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (landlordUid.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddReviewDialog(landlordUid, landlord);
                    },
                    icon: const Icon(
                      Icons.rate_review,
                      size: 16,
                      color: Colors.orangeAccent,
                    ),
                    label: const Text(
                      "Add Review",
                      style: TextStyle(color: Colors.orangeAccent),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      backgroundColor: Colors.orange.withOpacity(0.1),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showAddReviewDialog(String landlordUid, String landlordName) {
    final TextEditingController reviewController = TextEditingController();
    double rating = 5.0;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: Text(
              "Review $landlordName",
              style: const TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      "Rating: ",
                      style: TextStyle(color: Colors.white70),
                    ),
                    DropdownButton<double>(
                      dropdownColor: Colors.grey.shade900,
                      value: rating,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      underline: Container(),
                      items: [1.0, 2.0, 3.0, 4.0, 5.0]
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text("$e Stars"),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setStateSB(() => rating = val!),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: reviewController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "Write your review here...",
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (reviewController.text.trim().isEmpty) return;
                        setStateSB(() => isSubmitting = true);

                        final reviewData = {
                          "tenantName": _tenantName ?? "Anonymous Tenant",
                          "rating": rating,
                          "review": reviewController.text.trim(),
                          "timestamp": DateTime.now().toIso8601String(),
                        };

                        try {
                          // SDK Save
                          if (!kIsWeb &&
                              (Platform.isAndroid || Platform.isIOS)) {
                            await FirebaseFirestore.instance
                                .collection('reviews')
                                .doc(landlordUid)
                                .set({
                                  'reviews': FieldValue.arrayUnion([
                                    reviewData,
                                  ]),
                                }, SetOptions(merge: true));
                          }
                          // REST Save
                          else {
                            final commitUrl = Uri.parse(
                              '$kFirestoreBaseUrl:commit?key=$kFirebaseAPIKey',
                            );
                            final body = jsonEncode({
                              "writes": [
                                {
                                  "transform": {
                                    "document":
                                        "projects/$kProjectId/databases/(default)/documents/reviews/$landlordUid",
                                    "fieldTransforms": [
                                      {
                                        "fieldPath": "reviews",
                                        "appendMissingElements": {
                                          "values": [
                                            {
                                              "mapValue": {
                                                "fields": {
                                                  "tenantName": {
                                                    "stringValue":
                                                        reviewData["tenantName"]
                                                            .toString(),
                                                  },
                                                  "rating": {
                                                    "doubleValue":
                                                        reviewData["rating"],
                                                  },
                                                  "review": {
                                                    "stringValue":
                                                        reviewData["review"]
                                                            .toString(),
                                                  },
                                                  "timestamp": {
                                                    "stringValue":
                                                        reviewData["timestamp"]
                                                            .toString(),
                                                  },
                                                },
                                              },
                                            },
                                          ],
                                        },
                                      },
                                    ],
                                  },
                                },
                              ],
                            });
                            await http.post(
                              commitUrl,
                              body: body,
                              headers: {'Content-Type': 'application/json'},
                            );
                          }

                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Review added successfully!"),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setStateSB(() => isSubmitting = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Error: $e"),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Submit",
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const AnimatedGradientBackground(),
            SafeArea(
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
                            child: _isLoadingProfile
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : (_profilePicUrl == null
                                      ? const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: Colors.deepPurple,
                                        )
                                      : null),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _tenantName ?? "Tenant Name",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 30),

                          // --- UPDATED: Identity Verification Section ---
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Identity Verification",
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _isAadharVerified
                                          ? Icons.verified_user
                                          : Icons.warning_amber_rounded,
                                      color: _isAadharVerified
                                          ? Colors.green
                                          : Colors.orange,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      "Aadhaar Verification",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  _isAadharVerified
                                      ? "Your Aadhaar has been securely verified via DigiLocker."
                                      : "For security purposes, please verify your Aadhaar card using DigiLocker. No raw images are stored on our servers.",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                if (!_isAadharVerified)
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _verifyAadharWithDigiLocker,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue.shade700,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.security,
                                        color: Colors.white,
                                      ),
                                      label: const Text(
                                        "Verify with DigiLocker",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: const Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            "Verified by DigiLocker",
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // ----------------------------------------------
                          const SizedBox(height: 40),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "My Rented Homes",
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _isLoadingHomes
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : (_rentedHomes.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text(
                                          "No rented homes found.",
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _rentedHomes.length,
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemBuilder: (context, index) {
                                          final req = _rentedHomes[index];
                                          final String name =
                                              req['apartmentName'] ??
                                              "Rented Property";
                                          final String landlord =
                                              req['landlordName'] ??
                                              "Unknown Landlord";
                                          final String location =
                                              req['panchayat'] ??
                                              "Unknown Location";

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: GlassmorphismContainer(
                                              opacity: 0.1,
                                              child: ListTile(
                                                onTap: () =>
                                                    _showApartmentDetailsPopup(
                                                      req,
                                                    ), // CHANGED: Added tap to trigger popup
                                                leading: const Icon(
                                                  Icons.home,
                                                  color: Colors.greenAccent,
                                                ),
                                                title: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                subtitle: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      location,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "Landlord: $landlord",
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      )),
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
}

// =======================================================================
//  MOCK DIGILOCKER GATEWAY
// =======================================================================

class MockDigiLockerGateway extends StatefulWidget {
  final VoidCallback onSuccess;

  const MockDigiLockerGateway({super.key, required this.onSuccess});

  @override
  State<MockDigiLockerGateway> createState() => _MockDigiLockerGatewayState();
}

class _MockDigiLockerGatewayState extends State<MockDigiLockerGateway> {
  int _step = 1;
  final TextEditingController _aadharController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "DigiLocker KYC",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 15),
            if (_step == 1) ...[
              const Text(
                "Enter Aadhaar Number",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _aadharController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  hintText: "0000 0000 0000",
                  hintStyle: TextStyle(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  prefixIcon: const Icon(Icons.credit_card, color: Colors.grey),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          if (_aadharController.text.length != 12) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Enter a valid 12-digit Aadhaar"),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setState(() => _isProcessing = true);
                          await Future.delayed(const Duration(seconds: 1));
                          if (mounted) {
                            setState(() {
                              _isProcessing = false;
                              _step = 2;
                            });
                          }
                        },
                  child: _isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Get OTP",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ] else ...[
              const Text(
                "Enter OTP",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                "OTP sent to mobile linked with Aadhaar ending in ${_aadharController.text.substring(8)}",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  hintText: "123456",
                  hintStyle: TextStyle(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  prefixIcon: const Icon(Icons.message, color: Colors.grey),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          if (_otpController.text.length != 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Enter a valid 6-digit OTP"),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setState(() => _isProcessing = true);
                          final navigator = Navigator.of(context);
                          await Future.delayed(const Duration(seconds: 1));
                          if (context.mounted) {
                            navigator.pop(); // Close the mock gateway
                            widget.onSuccess(); // Trigger firestore update
                          }
                        },
                  child: _isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Verify",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
            const SizedBox(height: 15),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.security, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    "Secured by DigiLocker",
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

// 2. Paste the function right here, inside the class
Future<void> saveDeviceToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Request permission (Required for iOS and Android 13+)
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  // Get the unique device token
  String? token = await messaging.getToken();

  // Save it to the tenant's Firestore document
  if (token != null) {
    await FirebaseFirestore.instance.collection('tenant').doc(user.uid).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }

  // Update Firestore if the token ever changes
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    FirebaseFirestore.instance.collection('tenant').doc(user.uid).set({
      'fcmToken': newToken,
    }, SetOptions(merge: true));
  });
}
