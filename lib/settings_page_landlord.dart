import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:main_project/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant.dart';

dynamic _settingsParseFirestoreValue(Map<String, dynamic> valueMap) {
  if (valueMap.containsKey('stringValue')) return valueMap['stringValue'];
  if (valueMap.containsKey('integerValue')) {
    return int.tryParse(valueMap['integerValue'] ?? '0');
  }
  if (valueMap.containsKey('doubleValue')) {
    return double.tryParse(valueMap['doubleValue'] ?? '0.0');
  }
  if (valueMap.containsKey('booleanValue')) return valueMap['booleanValue'];
  return null;
}

Future<void> _settingsUploadFile(XFile file, String storagePath) async {
  // 1. SDK LOGIC (Mobile)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await FirebaseStorage.instance.ref(storagePath).putFile(File(file.path));
  }
  // 2. REST LOGIC (Web/Desktop)
  else {
    final bytes = await file.readAsBytes();
    String encodedPath = Uri.encodeComponent(storagePath);

    // First, try to get Auth Token
    String? token = await FirebaseAuth.instance.currentUser?.getIdToken();

    final uploadUrl = Uri.parse(
      '$kStorageBaseUrl?name=$encodedPath&uploadType=media&key=$kFirebaseAPIKey',
    );

    final response = await http.post(
      uploadUrl,
      headers: {
        "Content-Type": "application/octet-stream",
        "Content-Length": bytes.length.toString(),
        if (token != null) "Authorization": "Bearer $token",
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      throw "Upload failed: ${response.body}";
    }
  }
}

class SettingsPage extends StatelessWidget {
  final VoidCallback onBack;
  const SettingsPage({super.key, required this.onBack});

  static bool get useNativeSdk =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> settingsOptions = [
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
        'title': 'Notification ',
        'icon': Icons.notifications_none,
        'color': Colors.green,
        'action': (BuildContext context) {},
      },
      {
        'title': 'View My Profile',
        'icon': Icons.person,
        'color': Colors.purple,
        'action': (BuildContext context) {
          // --- RESTORED NAVIGATION LOGIC ---
          final uid = FirebaseAuth.instance.currentUser!.uid;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LandlordsearchProfilePage2(
                landlordUid: uid,
                propertyDetails: {
                  'roomType': 'N/A',
                  'location': 'N/A',
                  'rent': 'N/A',
                  'maxOccupancy': 'N/A',
                },
                propertyIndex: 0,
              ),
            ),
          );
        },
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
          const AnimatedGradientBackground(),
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
                        ...settingsOptions.map((option) {
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
                        }),
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
                                        onPressed: () async {
                                          await FirebaseAuth.instance.signOut();
                                          if (!context.mounted) return;
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
  static void _showEditProfileDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController aadharController = TextEditingController();

    XFile? pickedImageFile;
    XFile? pickedSignFile;
    bool isUpdating = false;
    bool isFetching = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, stfSetState) {
          // --- PRE-FETCH DATA ---
          if (isFetching) {
            //final String? uid = FirebaseAuth.instance.currentUser?.uid;
            Future.delayed(Duration.zero, () async {
              try {
                Map<String, dynamic>? data;

                if (useNativeSdk) {
                  // SDK
                  DocumentSnapshot doc = await FirebaseFirestore.instance
                      .collection('landlord')
                      .doc(uid)
                      .get();
                  if (doc.exists) {
                    data = doc.data() as Map<String, dynamic>;
                  }
                } else {
                  // REST
                  final url = Uri.parse(
                    '$kFirestoreBaseUrl/landlord/$uid?key=$kFirebaseAPIKey',
                  );
                  final response = await http.get(url);
                  if (response.statusCode == 200) {
                    final jsonData = jsonDecode(response.body);
                    if (jsonData['fields'] != null) {
                      data = {};
                      jsonData['fields'].forEach((key, val) {
                        data![key] = _settingsParseFirestoreValue(val);
                      });
                    }
                  }
                }

                if (data != null) {
                  nameController.text = data['fullName'] ?? '';
                  idController.text = data['profileName'] ?? '';
                  phoneController.text = data['phoneNumber'] ?? '';
                  aadharController.text = data['aadharNumber'] ?? '';
                }
              } catch (_) {
                // Ignore fetch errors
              } finally {
                stfSetState(() => isFetching = false);
              }
            });
          }

          if (isFetching) {
            return const Center(child: CircularProgressIndicator());
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
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
                      if (isUpdating) return;
                      final ImagePicker picker = ImagePicker();
                      try {
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          stfSetState(() {
                            pickedImageFile = image;
                          });
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to pick image'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade700,
                      backgroundImage: pickedImageFile != null
                          ? (kIsWeb
                                ? NetworkImage(pickedImageFile!.path)
                                : FileImage(File(pickedImageFile!.path))
                                      as ImageProvider)
                          : const AssetImage('assets/profile_placeholder.png')
                                as ImageProvider,
                      child: const Align(
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
                  const SizedBox(height: 15),
                  _buildInputField(nameController, "Full Name"),
                  _buildInputField(idController, "User ID"),
                  _buildInputField(phoneController, "Phone Number"),
                  _buildInputField(aadharController, "Aadhar Number"),
                  const SizedBox(height: 15),
                  GestureDetector(
                    onTap: () async {
                      if (isUpdating) return;
                      final ImagePicker picker = ImagePicker();
                      try {
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          stfSetState(() {
                            pickedSignFile = image;
                          });
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to pick signature'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade700,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade600),
                      ),
                      child: pickedSignFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: kIsWeb
                                  ? Image.network(
                                      pickedSignFile!.path,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      File(pickedSignFile!.path),
                                      fit: BoxFit.cover,
                                    ),
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.draw, color: Colors.white54),
                                  SizedBox(height: 5),
                                  Text(
                                    "Tap to upload Signature",
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: isUpdating
                    ? null
                    : () async {
                        final String aadhar = aadharController.text.trim();
                        if (aadhar.isNotEmpty && aadhar.length != 12) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Aadhar Number must be exactly 12 digits',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        stfSetState(() => isUpdating = true);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogContext);
                        final String? uid =
                            FirebaseAuth.instance.currentUser?.uid;

                        if (uid == null) return;

                        try {
                          // 1. Upload Profile Image
                          if (pickedImageFile != null) {
                            String filePath =
                                '$uid/profile_pic/profile_image.jpg';
                            await _settingsUploadFile(
                              pickedImageFile!,
                              filePath,
                            );
                          }

                          // 2. Upload Signature
                          if (pickedSignFile != null) {
                            String signPath = '$uid/sign/sign.jpg';
                            await _settingsUploadFile(
                              pickedSignFile!,
                              signPath,
                            );
                          }

                          // 3. Update Firestore
                          Map<String, dynamic> updateData = {};
                          final String newFullName = nameController.text.trim();
                          final String newProfileName = idController.text
                              .trim();
                          final String newPhoneNumber = phoneController.text
                              .trim();

                          if (newFullName.isNotEmpty) {
                            updateData['fullName'] = newFullName;
                          }
                          if (newProfileName.isNotEmpty) {
                            updateData['profileName'] = newProfileName;
                          }
                          if (newPhoneNumber.isNotEmpty) {
                            updateData['phoneNumber'] = newPhoneNumber;
                          }
                          if (aadhar.isNotEmpty) {
                            updateData['aadharNumber'] = aadhar;
                          }

                          if (updateData.isNotEmpty) {
                            if (useNativeSdk) {
                              // SDK Update
                              await FirebaseFirestore.instance
                                  .collection('landlord')
                                  .doc(uid)
                                  .update(updateData);

                              // Check/Add UserIds
                              if (newProfileName.isNotEmpty) {
                                final checkSnap = await FirebaseFirestore
                                    .instance
                                    .collection('UserIds')
                                    .where('UserId', isEqualTo: newProfileName)
                                    .limit(1)
                                    .get();
                                if (checkSnap.docs.isEmpty) {
                                  await FirebaseFirestore.instance
                                      .collection('UserIds')
                                      .add({'UserId': newProfileName});
                                }
                              }
                            } else {
                              // REST Update
                              Map<String, dynamic> fields = {};
                              updateData.forEach((key, value) {
                                fields[key] = {"stringValue": value};
                              });
                              String updateMask = updateData.keys
                                  .map((k) => "updateMask.fieldPaths=$k")
                                  .join("&");

                              String? token = await FirebaseAuth
                                  .instance
                                  .currentUser
                                  ?.getIdToken();

                              final tUrl = Uri.parse(
                                '$kFirestoreBaseUrl/landlord/$uid?$updateMask&key=$kFirebaseAPIKey',
                              );
                              await http.patch(
                                tUrl,
                                body: jsonEncode({"fields": fields}),
                                headers: {
                                  "Content-Type": "application/json",
                                  if (token != null)
                                    "Authorization": "Bearer $token",
                                },
                              );

                              // REST UserIds Check/Add (Simplified: just trying add)
                              if (newProfileName.isNotEmpty) {
                                final addUrl = Uri.parse(
                                  '$kFirestoreBaseUrl/UserIds?key=$kFirebaseAPIKey',
                                );
                                await http.post(
                                  addUrl,
                                  body: jsonEncode({
                                    "fields": {
                                      "UserId": {"stringValue": newProfileName},
                                    },
                                  }),
                                  headers: {
                                    "Content-Type": "application/json",
                                    if (token != null)
                                      "Authorization": "Bearer $token",
                                  },
                                );
                              }
                            }
                          }

                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Profile updated successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          navigator.pop();
                        } catch (e) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Update failed: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (navigator.context.mounted) {
                            stfSetState(() => isUpdating = false);
                          }
                        }
                      },
                child: isUpdating
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
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------- CHANGE PASSWORD DIALOG ----------------------
  static void _showChangePasswordDialog(BuildContext context) {
    final TextEditingController newPassController = TextEditingController();
    final TextEditingController confirmPassController = TextEditingController();
    bool isChangingPassword = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, stfSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
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
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: isChangingPassword
                    ? null
                    : () async {
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogContext);
                        final String newPassword = newPassController.text;
                        final String confirmPassword =
                            confirmPassController.text;

                        if (newPassword.isEmpty || confirmPassword.isEmpty) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Please fill both fields'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        if (newPassword != confirmPassword) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Passwords do not match'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        if (newPassword.length < 6) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Password too short (min 6)'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        User? user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        stfSetState(() => isChangingPassword = true);

                        try {
                          if (useNativeSdk) {
                            // SDK Logic
                            await user.updatePassword(newPassword);
                          } else {
                            // REST Logic (Identity Toolkit)
                            String? token = await user.getIdToken();
                            if (token == null) throw "Token missing";

                            final url = Uri.parse(
                              'https://identitytoolkit.googleapis.com/v1/accounts:update?key=$kFirebaseAPIKey',
                            );
                            final response = await http.post(
                              url,
                              body: jsonEncode({
                                "idToken": token,
                                "password": newPassword,
                                "returnSecureToken": true,
                              }),
                              headers: {"Content-Type": "application/json"},
                            );

                            if (response.statusCode != 200) {
                              throw "API Error: ${response.body}";
                            }
                          }

                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Password changed successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          navigator.pop();
                        } catch (e) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (navigator.context.mounted) {
                            stfSetState(() => isChangingPassword = false);
                          }
                        }
                      },
                child: isChangingPassword
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
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- HELPER: Build Input Field ---
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
