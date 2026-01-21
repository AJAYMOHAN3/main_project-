import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';
import 'tenant.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';

import 'dart:convert'; // For jsonDecode
import 'package:http/http.dart' as http; // Add http to pubspec.yaml

// --- GLOBAL CONSTANTS (Ensure these match your project) ---
const String kFirebaseAPIKey = "AIzaSyC61uOOK-kmotuQKTsCKIrkjDAYAQ5CYAw";
const String kProjectId = "homes-6b1dd";
const String kStorageBucket = "homes-6b1dd.firebasestorage.app";
const String kFirestoreBaseUrl =
    "https://firestore.googleapis.com/v1/projects/$kProjectId/databases/(default)/documents";
const String kStorageBaseUrl =
    "https://firebasestorage.googleapis.com/v0/b/$kStorageBucket/o";
const bool kIsWeb = bool.fromEnvironment('dart.library.js_util');

// --- CLASSES ---

class DocumentFields {
  String? selectedDoc;
  PlatformFile? pickedFile;
  DocumentFields({this.selectedDoc, this.pickedFile});
}

class LandlordPropertyForm {
  final TextEditingController apartmentNameController = TextEditingController();
  final TextEditingController roomTypeController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController rentController = TextEditingController();
  final TextEditingController maxOccupancyController = TextEditingController();
  final TextEditingController panchayatNameController = TextEditingController();
  final TextEditingController blockNoController = TextEditingController();
  final TextEditingController thandaperNoController = TextEditingController();
  final TextEditingController securityAmountController =
      TextEditingController();

  List<DocumentFields> documents;
  List<XFile> houseImages = [];

  LandlordPropertyForm({required this.documents});

  void dispose() {
    apartmentNameController.dispose();
    roomTypeController.dispose();
    locationController.dispose();
    rentController.dispose();
    maxOccupancyController.dispose();
    panchayatNameController.dispose();
    blockNoController.dispose();
    thandaperNoController.dispose();
    securityAmountController.dispose();
  }
}

class LandlordProfilePage extends StatefulWidget {
  final VoidCallback onBack;
  const LandlordProfilePage({super.key, required this.onBack});

  @override
  LandlordProfilePageState createState() => LandlordProfilePageState();
}

class LandlordProfilePageState extends State<LandlordProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<DocumentFields> newUserDocuments = [DocumentFields()];
  List<Reference> _fetchedUserDocs = [];
  bool _isLoadingDocs = true;

  List<LandlordPropertyForm> propertyCards = [
    LandlordPropertyForm(documents: [DocumentFields()]),
  ];
  bool _isUploading = false;

  List<Map<String, dynamic>> _myApartments = [];
  bool _isLoadingApartments = true;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchLandlordData();
    _fetchUserDocs();
    _fetchMyApartments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var card in propertyCards) {
      card.dispose();
    }
    super.dispose();
  }

  // ================= 1. DATA FETCHING =================

  Future<void> _fetchLandlordData() async {
    //final String? uid = FirebaseAuth.instance.currentUser?.uid;
    //if (uid == null) return;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('landlord')
            .doc(uid)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _landlordName = (doc.data() as Map<String, dynamic>)['fullName'];
          });
        }
        final ref = FirebaseStorage.instance.ref('$uid/profile_pic/');
        final list = await ref.list(const ListOptions(maxResults: 1));
        if (list.items.isNotEmpty) {
          String url = await list.items.first.getDownloadURL();
          if (mounted) setState(() => _profilePicUrl = url);
        }
      } catch (_) {}
    } else {
      try {
        final firestoreUrl = Uri.parse(
          '$kFirestoreBaseUrl/landlord/$uid?key=$kFirebaseAPIKey',
        );
        final fsResponse = await http.get(firestoreUrl);
        if (fsResponse.statusCode == 200) {
          final data = jsonDecode(fsResponse.body);
          if (data['fields'] != null && data['fields']['fullName'] != null) {
            setState(() {
              _landlordName = data['fields']['fullName']['stringValue'];
            });
          }
        }
        final storageListUrl = Uri.parse(
          '$kStorageBaseUrl?prefix=$uid/profile_pic/&key=$kFirebaseAPIKey',
        );
        final stResponse = await http.get(storageListUrl);
        if (stResponse.statusCode == 200) {
          final data = jsonDecode(stResponse.body);
          if (data['items'] != null && (data['items'] as List).isNotEmpty) {
            String objectName = data['items'][0]['name'];
            String encodedName = Uri.encodeComponent(objectName);
            String downloadUrl =
                '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
            if (mounted) setState(() => _profilePicUrl = downloadUrl);
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchUserDocs() async {
    //final String? uid = FirebaseAuth.instance.currentUser?.uid;
    //if (uid == null) return;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final list = await FirebaseStorage.instance
            .ref('$uid/user_docs/')
            .listAll();
        if (mounted) {
          setState(() {
            _fetchedUserDocs = list.items;
            _isLoadingDocs = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingDocs = false);
      }
    } else {
      try {
        final url = Uri.parse(
          '$kStorageBaseUrl?prefix=$uid/user_docs/&key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        List<Reference> mappedRefs = [];
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['items'] != null) {
            for (var item in data['items']) {
              String fullPath = item['name'];
              String fileName = fullPath.split('/').last;
              mappedRefs.add(
                RestReference(name: fileName, fullPath: fullPath) as Reference,
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _fetchedUserDocs = mappedRefs;
            _isLoadingDocs = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingDocs = false);
      }
    }
  }

  Future<void> _fetchMyApartments() async {
    //final String? uid = FirebaseAuth.instance.currentUser?.uid;
    //if (uid == null) return;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('house')
            .doc(uid)
            .get();
        if (doc.exists && mounted) {
          Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('properties')) {
            setState(() {
              _myApartments = List<Map<String, dynamic>>.from(
                data['properties'],
              );
              _isLoadingApartments = false;
            });
            return;
          }
        }
        setState(() => _isLoadingApartments = false);
      } catch (e) {
        if (mounted) setState(() => _isLoadingApartments = false);
      }
    } else {
      try {
        final url = Uri.parse(
          '$kFirestoreBaseUrl/house/$uid?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null && data['fields']['properties'] != null) {
            var rawList =
                data['fields']['properties']['arrayValue']['values'] as List?;
            if (rawList != null) {
              List<Map<String, dynamic>> parsedProps = [];
              for (var item in rawList) {
                if (item['mapValue'] != null &&
                    item['mapValue']['fields'] != null) {
                  Map<String, dynamic> cleanMap = {};
                  Map<String, dynamic> fields = item['mapValue']['fields'];
                  fields.forEach((key, val) {
                    cleanMap[key] = _parseFirestoreRestValue(val);
                  });
                  parsedProps.add(cleanMap);
                }
              }
              if (mounted) {
                setState(() {
                  _myApartments = parsedProps;
                  _isLoadingApartments = false;
                });
                return;
              }
            }
          }
        }
        if (mounted) setState(() => _isLoadingApartments = false);
      } catch (e) {
        if (mounted) setState(() => _isLoadingApartments = false);
      }
    }
  }

  // ================= 2. HELPERS =================

  Future<PlatformFile?> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
      withData: true,
    );
    if (result != null) {
      return result.files.single;
    }
    return null;
  }

  Future<void> _pickHouseImagesForCard(int index) async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isNotEmpty && mounted) {
      setState(() {
        propertyCards[index].houseImages.addAll(images);
      });
    }
  }

  // --- SMART UPLOAD: HANDLES FILE TYPES AND PLATFORMS ---
  Future<String?> _uploadFileWithReplace(
    dynamic fileInput,
    String folderPath,
    String fileNameWithoutExt,
  ) async {
    Uint8List? fileBytes;
    File? fileMobile;
    String extension = 'jpg';

    try {
      if (fileInput is PlatformFile) {
        extension = fileInput.extension ?? 'pdf';
        if (kIsWeb) {
          fileBytes = fileInput.bytes;
        } else {
          if (fileInput.path != null) {
            fileMobile = File(fileInput.path!);
          }
        }
      } else if (fileInput is XFile) {
        // FIX: Use .name for extension on Web/HTTP
        extension = fileInput.name.split('.').last;
        if (kIsWeb) {
          fileBytes = await fileInput.readAsBytes();
        } else {
          fileMobile = File(fileInput.path);
        }
      }
    } catch (e) {
      return null;
    }

    String fullFileName = '$fileNameWithoutExt.$extension';

    // 1. SDK LOGIC
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      if (fileMobile == null) return null;
      try {
        final folderRef = FirebaseStorage.instance.ref(folderPath);
        try {
          final listResult = await folderRef.listAll();
          for (var item in listResult.items) {
            if (item.name.split('.').first == fileNameWithoutExt) {
              await item.delete();
            }
          }
        } catch (_) {}

        final ref = FirebaseStorage.instance.ref('$folderPath/$fullFileName');
        await ref.putFile(fileMobile);
        return await ref.getDownloadURL();
      } catch (e) {
        return null;
      }
    }
    // 2. REST LOGIC
    else {
      if (fileBytes == null) return null;
      try {
        String fullPath = '$folderPath/$fullFileName';
        String encodedPath = Uri.encodeComponent(fullPath);

        // Standard upload
        String uploadUrl =
            "$kStorageBaseUrl?name=$encodedPath&uploadType=media&key=$kFirebaseAPIKey";

        var response = await http.post(
          Uri.parse(uploadUrl),
          body: fileBytes,
          headers: {"Content-Type": "application/octet-stream"},
        );

        if (response.statusCode == 200) {
          return "$kStorageBaseUrl/$encodedPath?alt=media&key=$kFirebaseAPIKey";
        }
        return null;
      } catch (e) {
        return null;
      }
    }
  }

  Future<void> _openFile(Reference ref) async {
    try {
      String url = await ref.getDownloadURL();
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch file viewer")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ================= 3. UPLOAD LOGIC =================

  int _getNextPropertyFolderIndex() {
    int maxIndex = 0;
    for (var apt in _myApartments) {
      String folderName = apt['folderName'] ?? '';
      if (folderName.startsWith('property')) {
        String numPart = folderName.replaceFirst('property', '');
        int? index = int.tryParse(numPart);
        if (index != null && index > maxIndex) {
          maxIndex = index;
        }
      }
    }
    return maxIndex + 1;
  }

  Future<void> _updateExistingDoc(Reference ref) async {
    PlatformFile? file = await _pickDocument();
    if (file != null) {
      String baseName = ref.name.split('.').first;
      //String? uid = FirebaseAuth.instance.currentUser?.uid;
      //if (uid == null) return;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Updating document...")));

      await _uploadFileWithReplace(file, '$uid/user_docs', baseName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Document updated!"),
          backgroundColor: Colors.green,
        ),
      );
      _fetchUserDocs();
    }
  }

  Future<void> _uploadNewProperty() async {
    //final String? uid = FirebaseAuth.instance.currentUser?.uid;
    //if (uid == null) return;

    setState(() => _isUploading = true);

    try {
      List<Map<String, dynamic>> newProps = [];
      int nextFolderNum = _getNextPropertyFolderIndex();

      for (var card in propertyCards) {
        // FIX: Check if apartment name is empty to prevent ghost entries
        if (card.apartmentNameController.text.trim().isEmpty) {
          continue;
        }

        String folderName = 'property$nextFolderNum';
        List<String> docUrls = [];
        List<String> imageUrls = [];

        // Upload Docs
        for (var doc in card.documents) {
          if (doc.selectedDoc != null && doc.pickedFile != null) {
            String? url = await _uploadFileWithReplace(
              doc.pickedFile,
              '$uid/$folderName',
              doc.selectedDoc!,
            );
            if (url != null) docUrls.add(url);
          }
        }

        // Upload Images
        for (int i = 0; i < card.houseImages.length; i++) {
          String? url = await _uploadFileWithReplace(
            card.houseImages[i],
            '$uid/$folderName/images',
            'image_$i',
          );
          if (url != null) imageUrls.add(url);
        }

        newProps.add({
          'apartmentName': card.apartmentNameController.text,
          'roomType': card.roomTypeController.text,
          'location': card.locationController.text,
          'rent': card.rentController.text,
          'maxOccupancy': card.maxOccupancyController.text,
          'folderName': folderName,
          'documentUrls': docUrls,
          'houseImageUrls': imageUrls,
          'panchayatName': card.panchayatNameController.text,
          'blockNo': card.blockNoController.text,
          'thandaperNo': card.thandaperNoController.text,
          'securityAmount': card.securityAmountController.text,
        });

        nextFolderNum++;
      }

      // Upload New User Docs (Always do this if they exist)
      for (var doc in newUserDocuments) {
        if (doc.selectedDoc != null && doc.pickedFile != null) {
          await _uploadFileWithReplace(
            doc.pickedFile,
            '$uid/user_docs',
            doc.selectedDoc!,
          );
        }
      }

      // FIX: Only perform Firestore update if we actually added new properties
      if (newProps.isNotEmpty) {
        // 1. SDK SAVE
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          await FirebaseFirestore.instance.collection('house').doc(uid).set({
            'properties': FieldValue.arrayUnion(newProps),
          }, SetOptions(merge: true));
        }
        // 2. REST SAVE
        else {
          List<Map<String, dynamic>> allProps = List.from(_myApartments);
          allProps.addAll(newProps);

          List<Map<String, dynamic>> jsonValues = allProps
              .map((p) => _encodeMapForFirestore(p))
              .toList();

          Map<String, dynamic> body = {
            "fields": {
              "properties": {
                "arrayValue": {"values": jsonValues},
              },
            },
          };

          // Use ?currentDocument.exists=true to ensure we don't overwrite blindly, or simpler, assume exists/create.
          // Firestore REST usually requires patch.
          final url = Uri.parse(
            '$kFirestoreBaseUrl/house/$uid?key=$kFirebaseAPIKey',
          );
          await http.patch(
            url,
            body: jsonEncode(body),
            headers: {"Content-Type": "application/json"},
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Upload Successful!"),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        propertyCards = [
          LandlordPropertyForm(documents: [DocumentFields()]),
        ];
        newUserDocuments = [DocumentFields()];
        _isUploading = false;
      });
      _fetchMyApartments();
      _fetchUserDocs();
      // Optional: switch tab if property was added
      if (newProps.isNotEmpty) {
        _tabController.animateTo(2);
      }
    } catch (e) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- Delete Property ---
  Future<void> _deleteApartment(int index) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E2A47),
            title: const Text(
              "Delete Property?",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "This will mark the listing as deleted.",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;
    setState(() => _isLoadingApartments = true);

    Map<String, dynamic> prop = _myApartments[index];

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await FirebaseFirestore.instance.collection('house').doc(uid).update({
          'properties': FieldValue.arrayRemove([prop]),
        });
        prop['status'] = 'deleted';
        await FirebaseFirestore.instance.collection('house').doc(uid).update({
          'properties': FieldValue.arrayUnion([prop]),
        });
        _fetchMyApartments();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Property marked as deleted"),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (mounted) setState(() => _isLoadingApartments = false);
      }
    } else {
      try {
        _myApartments[index]['status'] = 'deleted';
        List<Map<String, dynamic>> jsonValues = _myApartments
            .map((p) => _encodeMapForFirestore(p))
            .toList();

        Map<String, dynamic> body = {
          "fields": {
            "properties": {
              "arrayValue": {"values": jsonValues},
            },
          },
        };

        final url = Uri.parse(
          '$kFirestoreBaseUrl/house/$uid?key=$kFirebaseAPIKey',
        );
        await http.patch(
          url,
          body: jsonEncode(body),
          headers: {"Content-Type": "application/json"},
        );

        _fetchMyApartments();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Property marked as deleted"),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (mounted) setState(() => _isLoadingApartments = false);
      }
    }
  }

  // --- Update Property Images ---
  Future<void> _updateApartmentFiles(int index) async {
    //final String? uid = FirebaseAuth.instance.currentUser?.uid;
    //if (uid == null) return;

    Map<String, dynamic> prop = _myApartments[index];
    String folderName = prop['folderName'] ?? 'property${index + 1}';

    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();

    if (images.isEmpty) return;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Uploading new images...")));

    List<String> newUrls = [];
    for (var img in images) {
      String name = 'image_update_${DateTime.now().millisecondsSinceEpoch}';
      String? url = await _uploadFileWithReplace(
        img,
        '$uid/$folderName/images',
        name,
      );
      if (url != null) newUrls.add(url);
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      List<dynamic> existingUrls = prop['houseImageUrls'] ?? [];
      List<dynamic> updatedUrls = [...existingUrls, ...newUrls];
      await FirebaseFirestore.instance.collection('house').doc(uid).update({
        'properties': FieldValue.arrayRemove([prop]),
      });
      prop['houseImageUrls'] = updatedUrls;
      await FirebaseFirestore.instance.collection('house').doc(uid).update({
        'properties': FieldValue.arrayUnion([prop]),
      });
    } else {
      List<dynamic> existingUrls = prop['houseImageUrls'] ?? [];
      List<dynamic> updatedUrls = [...existingUrls, ...newUrls];
      _myApartments[index]['houseImageUrls'] = updatedUrls;

      List<Map<String, dynamic>> jsonValues = _myApartments
          .map((p) => _encodeMapForFirestore(p))
          .toList();

      Map<String, dynamic> body = {
        "fields": {
          "properties": {
            "arrayValue": {"values": jsonValues},
          },
        },
      };

      final url = Uri.parse(
        '$kFirestoreBaseUrl/house/$uid?key=$kFirebaseAPIKey',
      );
      await http.patch(
        url,
        body: jsonEncode(body),
        headers: {"Content-Type": "application/json"},
      );
    }

    _fetchMyApartments();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Images updated!"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Map<String, dynamic> _encodeMapForFirestore(Map<String, dynamic> map) {
    Map<String, dynamic> fields = {};
    map.forEach((k, v) {
      if (v == null) return;
      if (v is String) {
        fields[k] = {"stringValue": v};
      } else if (v is int) {
        fields[k] = {"integerValue": v.toString()};
      } else if (v is double) {
        fields[k] = {"doubleValue": v.toString()};
      } else if (v is bool) {
        fields[k] = {"booleanValue": v};
      } else if (v is List) {
        fields[k] = {
          "arrayValue": {
            "values": v.map((e) => {"stringValue": e.toString()}).toList(),
          },
        };
      }
    });
    return {
      "mapValue": {"fields": fields},
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          widget.onBack();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Container(color: const Color(0xFF141E30)),
            SafeArea(
              child: Column(
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: "Landlord Profile",
                    onBack: widget.onBack,
                  ),
                  const SizedBox(height: 10),
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white12,
                    backgroundImage: _profilePicUrl != null
                        ? NetworkImage(_profilePicUrl!)
                        : null,
                    child: _profilePicUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.deepPurple,
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _landlordName ?? "Landlord Name",
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 15),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.orange,
                    labelColor: Colors.orange,
                    unselectedLabelColor: Colors.white60,
                    isScrollable: false,
                    tabs: const [
                      Tab(text: "User Docs"),
                      Tab(text: "Add Property"),
                      Tab(text: "My Apartments"),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildUserDocsTab(),
                        _buildAddPropertyTab(),
                        _buildMyApartmentsTab(),
                      ],
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

  Widget _buildUserDocsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Uploaded Documents",
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _isLoadingDocs
              ? const Center(child: CircularProgressIndicator())
              : _fetchedUserDocs.isEmpty
              ? const Text(
                  "No documents uploaded yet.",
                  style: TextStyle(color: Colors.white54),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _fetchedUserDocs.length,
                  itemBuilder: (ctx, i) {
                    final ref = _fetchedUserDocs[i];
                    return Card(
                      color: Colors.white10,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _openFile(ref),
                        leading: const Icon(
                          Icons.description,
                          color: Colors.blueAccent,
                        ),
                        title: Text(
                          ref.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: SizedBox(
                          width: 80,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => _updateExistingDoc(ref),
                            child: const Text(
                              "Update",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          const Divider(color: Colors.white24, height: 40),
          Text(
            "Upload New Documents",
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ListView.builder(
            itemCount: newUserDocuments.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, i) => _buildCompactDocRow(
              newUserDocuments[i],
              onRemove: () => setState(() => newUserDocuments.removeAt(i)),
              docOptions: userDocOptions,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () =>
                setState(() => newUserDocuments.add(DocumentFields())),
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text(
              "Add Another Doc",
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 20),
          if (newUserDocuments.any((d) => d.pickedFile != null))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _uploadNewProperty,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  "Upload Selected Docs",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddPropertyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListView.builder(
            itemCount: propertyCards.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPropertyCard(i),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => setState(
              () => propertyCards.add(
                LandlordPropertyForm(documents: [DocumentFields()]),
              ),
            ),
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text(
              "Add Another Unit",
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isUploading ? null : _uploadNewProperty,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isUploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "UPLOAD PROPERTY",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyApartmentsTab() {
    if (_isLoadingApartments) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_myApartments.isEmpty) {
      return const Center(
        child: Text(
          "No apartments listed yet.",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchMyApartments,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myApartments.length,
        itemBuilder: (ctx, index) {
          final apt = _myApartments[index];
          String folderName = 'property${index + 1}';
          List<dynamic> images = apt['houseImageUrls'] ?? [];
          String thumbUrl = images.isNotEmpty ? images.first : '';

          String displayName =
              (apt['apartmentName'] != null &&
                  apt['apartmentName'].toString().isNotEmpty)
              ? apt['apartmentName']
              : "My Apartment";

          return Card(
            color: Colors.white.withValues(alpha: 0.1),
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    image: thumbUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(thumbUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: thumbUrl.isEmpty
                      ? const Center(
                          child: Icon(
                            Icons.home,
                            color: Colors.white54,
                            size: 40,
                          ),
                        )
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              folderName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "${apt['roomType'] ?? 'Unknown'} • ${apt['location'] ?? ''}",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        "Rent: ₹${apt['rent']}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => _updateApartmentFiles(index),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blueAccent),
                            ),
                            child: const Text(
                              "Add Images",
                              style: TextStyle(color: Colors.blueAccent),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => _deleteApartment(index),
                            child: const Text(
                              "Delete",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactDocRow(
    DocumentFields docField, {
    required VoidCallback onRemove,
    required List<String> docOptions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: docField.selectedDoc,
              hint: const Text(
                "Select Doc",
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              underline: Container(),
              items: docOptions
                  .map((doc) => DropdownMenuItem(value: doc, child: Text(doc)))
                  .toList(),
              onChanged: (val) => setState(() => docField.selectedDoc = val),
            ),
          ),
          if (docField.pickedFile != null) ...[
            Expanded(
              child: Text(
                docField.pickedFile!.name,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
              onPressed: () => setState(() => docField.pickedFile = null),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ] else ...[
            TextButton(
              onPressed: docField.selectedDoc == null
                  ? null
                  : () async {
                      PlatformFile? picked = await _pickDocument();
                      if (picked != null) {
                        setState(() => docField.pickedFile = picked);
                      }
                    },
              child: const Text("Pick", style: TextStyle(fontSize: 12)),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            onPressed: onRemove,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.only(left: 8),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyCard(int index) {
    final property = propertyCards[index];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Property Details",
                style: TextStyle(
                  color: Colors.orange.shade300,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
                onPressed: () {
                  property.dispose();
                  setState(() => propertyCards.removeAt(index));
                },
              ),
            ],
          ),
          _compactTextField(property.apartmentNameController, "Apartment Name"),
          const SizedBox(height: 8),
          _compactTextField(property.roomTypeController, "Room Type (1BHK)"),
          const SizedBox(height: 8),
          _compactTextField(property.locationController, "Location"),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  property.panchayatNameController,
                  "Panchayat Name",
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  property.blockNoController,
                  "Block No.",
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  property.thandaperNoController,
                  "Thandaper No.",
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  property.securityAmountController,
                  "Security Amount",
                  isNumber: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  property.rentController,
                  "Rent",
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  property.maxOccupancyController,
                  "Max Occupants",
                  isNumber: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Documents:",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Column(
            children: property.documents
                .asMap()
                .entries
                .map(
                  (e) => _buildCompactDocRow(
                    property.documents[e.key],
                    onRemove: () =>
                        setState(() => property.documents.removeAt(e.key)),
                    docOptions: propertyDocOptions,
                  ),
                )
                .toList(),
          ),
          TextButton.icon(
            onPressed: () =>
                setState(() => property.documents.add(DocumentFields())),
            icon: const Icon(Icons.add, size: 14),
            label: const Text("Add Doc", style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Divider(color: Colors.white12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Images:",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 5),
          if (property.houseImages.isNotEmpty)
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: property.houseImages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 5),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: kIsWeb
                      ? Image.network(
                          property.houseImages[i].path,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          File(property.houseImages[i].path),
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => _pickHouseImagesForCard(index),
            icon: const Icon(Icons.image, size: 14),
            label: const Text("Select Images", style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _compactTextField(
    TextEditingController controller,
    String hint, {
    bool isNumber = false,
  }) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// ================= HELPER CLASSES FOR REST =================

dynamic _parseFirestoreRestValue(Map<String, dynamic> valueMap) {
  if (valueMap.containsKey('stringValue')) return valueMap['stringValue'];
  if (valueMap.containsKey('integerValue')) {
    return int.tryParse(valueMap['integerValue'] ?? '0');
  }
  if (valueMap.containsKey('doubleValue')) {
    return double.tryParse(valueMap['doubleValue'] ?? '0.0');
  }
  if (valueMap.containsKey('booleanValue')) return valueMap['booleanValue'];

  if (valueMap.containsKey('arrayValue')) {
    var values = valueMap['arrayValue']['values'] as List?;
    if (values == null) return [];
    return values.map((v) => _parseFirestoreRestValue(v)).toList();
  }
  return null;
}

class RestReference implements Reference {
  @override
  final String name;
  @override
  final String fullPath;

  RestReference({required this.name, required this.fullPath});

  @override
  Future<String> getDownloadURL() async {
    String encodedName = Uri.encodeComponent(fullPath);
    return '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
  }

  @override
  String get bucket => kStorageBucket;

  @override
  FirebaseStorage get storage => throw UnimplementedError();
  @override
  Reference get root => throw UnimplementedError();
  @override
  Reference get parent => throw UnimplementedError();
  @override
  Reference child(String path) => throw UnimplementedError();
  @override
  Future<void> delete() => throw UnimplementedError();
  @override
  Future<FullMetadata> getMetadata() => throw UnimplementedError();
  @override
  Future<ListResult> list([ListOptions? options]) => throw UnimplementedError();
  @override
  Future<ListResult> listAll() => throw UnimplementedError();
  @override
  Future<Uint8List?> getData([int maxDownloadSizeBytes = 10485760]) =>
      throw UnimplementedError();

  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  UploadTask putBlob(dynamic blob, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  UploadTask putFile(File file, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  Future<FullMetadata> updateMetadata(SettableMetadata metadata) =>
      throw UnimplementedError();
  @override
  UploadTask putString(
    String data, {
    PutStringFormat format = PutStringFormat.raw,
    SettableMetadata? metadata,
  }) => throw UnimplementedError();

  @override
  DownloadTask writeToFile(File file) => throw UnimplementedError();
}

dynamic _requestsParseFirestoreValue(Map<String, dynamic> valueMap) {
  if (valueMap.containsKey('stringValue')) return valueMap['stringValue'];
  if (valueMap.containsKey('integerValue')) {
    return int.tryParse(valueMap['integerValue'] ?? '0');
  }
  if (valueMap.containsKey('doubleValue')) {
    return double.tryParse(valueMap['doubleValue'] ?? '0.0');
  }
  if (valueMap.containsKey('booleanValue')) return valueMap['booleanValue'];
  if (valueMap.containsKey('arrayValue')) {
    var values = valueMap['arrayValue']['values'] as List?;
    if (values == null) return [];
    return values.map((v) => _requestsParseFirestoreValue(v)).toList();
  }
  if (valueMap.containsKey('mapValue')) {
    var fields = valueMap['mapValue']['fields'] as Map<String, dynamic>?;
    if (fields == null) return {};
    Map<String, dynamic> result = {};
    fields.forEach((key, val) {
      result[key] = _requestsParseFirestoreValue(val);
    });
    return result;
  }
  return null;
}

class RequestsPage extends StatefulWidget {
  final VoidCallback onBack;
  const RequestsPage({super.key, required this.onBack});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  final String currentLandlordUid = uid;

  // Helper to determine platform
  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // --- REST API: Fetch Requests ---
  Future<List<dynamic>> _fetchRequestsRest() async {
    if (currentLandlordUid.isEmpty) return [];
    try {
      final url = Uri.parse(
        '$kFirestoreBaseUrl/lrequests/$currentLandlordUid?key=$kFirebaseAPIKey',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['fields'] != null && data['fields']['requests'] != null) {
          var rawList =
              data['fields']['requests']['arrayValue']['values'] as List?;
          if (rawList != null) {
            return rawList.map((v) => _requestsParseFirestoreValue(v)).toList();
          }
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),
          SafeArea(
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
                Expanded(
                  child: currentLandlordUid.isEmpty
                      ? const Center(
                          child: Text(
                            "Please login.",
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                      : useNativeSdk
                      // --- MOBILE: SDK STREAM ---
                      ? StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('lrequests')
                              .doc(currentLandlordUid)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snapshot.hasData || !snapshot.data!.exists) {
                              return _buildEmptyState();
                            }
                            final data =
                                snapshot.data!.data() as Map<String, dynamic>;
                            final List<dynamic> requests =
                                data['requests'] ?? [];
                            return _buildRequestsList(requests);
                          },
                        )
                      // --- WEB/DESKTOP: REST FUTURE ---
                      : FutureBuilder<List<dynamic>>(
                          future: _fetchRequestsRest(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return _buildEmptyState();
                            }
                            return _buildRequestsList(snapshot.data!);
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        "No requests received yet.",
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildRequestsList(List<dynamic> requests) {
    final pendingRequests = requests
        .where((r) => r['status'] == 'pending')
        .toList();

    if (pendingRequests.isEmpty) {
      return const Center(
        child: Text(
          "No pending requests.",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.builder(
      itemCount: pendingRequests.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final req = pendingRequests[index] as Map<String, dynamic>;
        final String tuid = req['tuid'] ?? '';
        final int propertyIndex = req['propertyIndex'] ?? 0;

        return _RequestItem(
          landlordUid: currentLandlordUid,
          tenantUid: tuid,
          propertyIndex: propertyIndex,
          requestData: req,
          requestIndex: requests.indexOf(req),
          useNativeSdk: useNativeSdk,
        );
      },
    );
  }
}

// --- Helper Widget for Individual List Item ---
class _RequestItem extends StatelessWidget {
  final String landlordUid;
  final String tenantUid;
  final int propertyIndex;
  final Map<String, dynamic> requestData;
  final int requestIndex;
  final bool useNativeSdk;

  const _RequestItem({
    required this.landlordUid,
    required this.tenantUid,
    required this.propertyIndex,
    required this.requestData,
    required this.requestIndex,
    required this.useNativeSdk,
  });

  // --- Hybrid Fetch Logic ---
  Future<Map<String, dynamic>> _fetchData() async {
    Map<String, dynamic> result = {};

    if (useNativeSdk) {
      // SDK Logic
      final houseSnap = await FirebaseFirestore.instance
          .collection('house')
          .doc(landlordUid)
          .get();
      if (houseSnap.exists) {
        result['house'] = houseSnap.data();
      }
      final tenantSnap = await FirebaseFirestore.instance
          .collection('tenant')
          .doc(tenantUid)
          .get();
      if (tenantSnap.exists) {
        result['tenant'] = tenantSnap.data();
      }
    } else {
      // REST Logic
      // 1. Fetch House
      final houseUrl = Uri.parse(
        '$kFirestoreBaseUrl/house/$landlordUid?key=$kFirebaseAPIKey',
      );
      final houseResp = await http.get(houseUrl);
      if (houseResp.statusCode == 200) {
        final data = jsonDecode(houseResp.body);
        if (data['fields'] != null) {
          Map<String, dynamic> clean = {};
          data['fields'].forEach((k, v) {
            clean[k] = _requestsParseFirestoreValue(v);
          });
          result['house'] = clean;
        }
      }

      // 2. Fetch Tenant
      final tenantUrl = Uri.parse(
        '$kFirestoreBaseUrl/tenant/$tenantUid?key=$kFirebaseAPIKey',
      );
      final tenantResp = await http.get(tenantUrl);
      if (tenantResp.statusCode == 200) {
        final data = jsonDecode(tenantResp.body);
        if (data['fields'] != null) {
          Map<String, dynamic> clean = {};
          data['fields'].forEach((k, v) {
            clean[k] = _requestsParseFirestoreValue(v);
          });
          result['tenant'] = clean;
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            color: Colors.white10,
            child: SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        String location = "Unknown Location";
        String roomType = "Property";
        String? imageUrl;
        String tenantName = "Unknown Tenant";

        if (snapshot.hasData) {
          final data = snapshot.data!;
          // Parse House
          if (data['house'] != null) {
            final List<dynamic> properties = data['house']['properties'] ?? [];
            if (propertyIndex < properties.length) {
              final prop = properties[propertyIndex];
              location = prop['location'] ?? "Unknown";
              roomType = prop['apartmentName'] ?? "My Apartment";
              final List<dynamic> images = prop['houseImageUrls'] ?? [];
              if (images.isNotEmpty) imageUrl = images[0];
            }
          }
          // Parse Tenant
          if (data['tenant'] != null) {
            tenantName = data['tenant']['fullName'] ?? "Unknown Tenant";
          }
        }

        return Card(
          color: Colors.white.withValues(alpha: 0.1),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.all(8),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 60,
                height: 60,
                color: Colors.black26,
                child: imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : const Icon(Icons.home, color: Colors.white54),
              ),
            ),
            title: Text(
              tenantName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(roomType, style: const TextStyle(color: Colors.white70)),
                Text(
                  location,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white54,
              size: 16,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TenantProfilePage(
                    tenantUid: tenantUid,
                    tenantName: tenantName,
                    landlordUid: landlordUid,
                    propertyIndex: propertyIndex,
                    requestIndex: requestIndex,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================================
// TENANT PROFILE PAGE (Accept/Reject & PDF Logic)
// ============================================================================

class TenantProfilePage extends StatefulWidget {
  final String tenantUid;
  final String tenantName;
  final String landlordUid;
  final int propertyIndex;
  final int requestIndex;

  const TenantProfilePage({
    super.key,
    required this.tenantUid,
    required this.tenantName,
    required this.landlordUid,
    required this.propertyIndex,
    required this.requestIndex,
  });

  @override
  State<TenantProfilePage> createState() => _TenantProfilePageState();
}

class _TenantProfilePageState extends State<TenantProfilePage> {
  String? _profilePicUrl;
  String? _apartmentName;
  List<Reference> _userDocs = [];
  bool _isLoadingImg = true;
  bool _isLoadingDocs = true;
  bool _isProcessing = false;

  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _fetchTenantProfilePic();
    _fetchRequestDetails();
    _fetchUserDocs();
  }

  Future<void> _fetchRequestDetails() async {
    try {
      if (useNativeSdk) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('lrequests')
            .doc(widget.landlordUid)
            .get();
        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          List<dynamic> requests = data['requests'] ?? [];
          if (widget.requestIndex < requests.length) {
            if (mounted) {
              setState(() {
                _apartmentName =
                    requests[widget.requestIndex]['apartmentName'] ??
                    "Property #${widget.propertyIndex + 1}";
              });
            }
          }
        }
      } else {
        // REST
        final url = Uri.parse(
          '$kFirestoreBaseUrl/lrequests/${widget.landlordUid}?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null) {
            var requests =
                _requestsParseFirestoreValue(data['fields']['requests'])
                    as List?;
            if (requests != null && widget.requestIndex < requests.length) {
              if (mounted) {
                setState(() {
                  _apartmentName =
                      requests[widget.requestIndex]['apartmentName'] ??
                      "Property #${widget.propertyIndex + 1}";
                });
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchUserDocs() async {
    try {
      if (useNativeSdk) {
        final storageRef = FirebaseStorage.instance.ref(
          '${widget.tenantUid}/user_docs/',
        );
        final listResult = await storageRef.listAll();
        if (mounted) {
          setState(() {
            _userDocs = listResult.items;
            _isLoadingDocs = false;
          });
        }
      } else {
        // REST List
        final prefix = '${widget.tenantUid}/user_docs/';
        final url = Uri.parse(
          '$kStorageBaseUrl?prefix=${Uri.encodeComponent(prefix)}&key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List<Reference> mappedRefs = [];
          if (data['items'] != null) {
            for (var item in data['items']) {
              String fullPath = item['name'];
              String fileName = fullPath.split('/').last;
              mappedRefs.add(
                RestReference(name: fileName, fullPath: fullPath) as Reference,
              );
            }
          }
          if (mounted) {
            setState(() {
              _userDocs = mappedRefs;
              _isLoadingDocs = false;
            });
          }
        } else {
          if (mounted) setState(() => _isLoadingDocs = false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingDocs = false);
    }
  }

  Future<void> _fetchTenantProfilePic() async {
    try {
      if (useNativeSdk) {
        final ref = FirebaseStorage.instance.ref(
          '${widget.tenantUid}/profile_pic/',
        );
        final list = await ref.list(const ListOptions(maxResults: 1));
        if (list.items.isNotEmpty) {
          String url = await list.items.first.getDownloadURL();
          if (mounted) setState(() => _profilePicUrl = url);
        }
      } else {
        // REST
        final prefix = '${widget.tenantUid}/profile_pic/';
        final url = Uri.parse(
          '$kStorageBaseUrl?prefix=${Uri.encodeComponent(prefix)}&key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['items'] != null && (data['items'] as List).isNotEmpty) {
            String objectName = data['items'][0]['name'];
            String encodedName = Uri.encodeComponent(objectName);
            String url =
                '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
            if (mounted) setState(() => _profilePicUrl = url);
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingImg = false);
    }
  }

  Future<void> _openDocument(Reference ref) async {
    try {
      String url = await ref.getDownloadURL();
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open document")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error opening file: $e")));
    }
  }

  // --- Hybrid Image Bytes Fetcher ---
  Future<Uint8List?> _fetchImageBytes(
    String storagePath, {
    bool isListing = false,
  }) async {
    try {
      if (useNativeSdk) {
        // SDK
        if (isListing) {
          final ref = FirebaseStorage.instance.ref(storagePath);
          final list = await ref.list(const ListOptions(maxResults: 1));
          if (list.items.isNotEmpty) {
            return await list.items.first.getData();
          }
        } else {
          final ref = FirebaseStorage.instance.ref(storagePath);
          return await ref.getData();
        }
      } else {
        // REST
        String targetPath = storagePath;
        if (isListing) {
          // List first, then get
          final listUrl = Uri.parse(
            '$kStorageBaseUrl?prefix=${Uri.encodeComponent(storagePath)}&key=$kFirebaseAPIKey',
          );
          final listResp = await http.get(listUrl);
          if (listResp.statusCode == 200) {
            final data = jsonDecode(listResp.body);
            if (data['items'] != null && (data['items'] as List).isNotEmpty) {
              targetPath = data['items'][0]['name']; // full path
            } else {
              return null;
            }
          } else {
            return null;
          }
        }
        // Download bytes
        String encodedPath = Uri.encodeComponent(targetPath);

        final downloadUrl =
            '$kStorageBaseUrl/$encodedPath?alt=media&key=$kFirebaseAPIKey';
        final response = await http.get(Uri.parse(downloadUrl));
        if (response.statusCode == 200) {
          return response.bodyBytes;
        }
      }
    } catch (_) {}
    return null;
  }

  // --- Hybrid File Upload ---
  Future<void> _uploadPdf(Uint8List bytes, String path) async {
    if (useNativeSdk) {
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
    } else {
      String encodedPath = Uri.encodeComponent(path);
      String? token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final url = Uri.parse(
        '$kStorageBaseUrl?name=$encodedPath&uploadType=media&key=$kFirebaseAPIKey',
      );

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/pdf",
          if (token != null) "Authorization": "Bearer $token",
        },
        body: bytes,
      );
      if (response.statusCode != 200) throw "Upload Failed";
    }
  }

  // --- Hybrid Firestore Update (Requests) ---
  Future<void> _updateRequestStatus(
    String collection,
    String uid,
    List<dynamic> updatedRequests,
  ) async {
    if (useNativeSdk) {
      await FirebaseFirestore.instance.collection(collection).doc(uid).update({
        'requests': updatedRequests,
      });
    } else {
      // REST Update
      String? token = await FirebaseAuth.instance.currentUser?.getIdToken();

      // Convert list to Firestore JSON
      Map<String, dynamic> jsonVal = {
        "arrayValue": {
          "values": updatedRequests.map((r) {
            Map<String, dynamic> fields = {};
            r.forEach((k, v) {
              if (v is String) {
                fields[k] = {"stringValue": v};
              } else if (v is int) {
                fields[k] = {"integerValue": v.toString()};
              }
              // Add other types if needed
            });
            return {
              "mapValue": {"fields": fields},
            };
          }).toList(),
        },
      };

      final url = Uri.parse(
        '$kFirestoreBaseUrl/$collection/$uid?updateMask.fieldPaths=requests&key=$kFirebaseAPIKey',
      );

      await http.patch(
        url,
        body: jsonEncode({
          "fields": {"requests": jsonVal},
        }),
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
      );
    }
  }

  // --- Hybrid Data Fetch for Agreement ---
  Future<Map<String, dynamic>> _fetchDocData(String col, String uid) async {
    if (useNativeSdk) {
      final doc = await FirebaseFirestore.instance
          .collection(col)
          .doc(uid)
          .get();
      return doc.data() ?? {};
    } else {
      final url = Uri.parse(
        '$kFirestoreBaseUrl/$col/$uid?key=$kFirebaseAPIKey',
      );
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['fields'] != null) {
          Map<String, dynamic> res = {};
          data['fields'].forEach((k, v) {
            res[k] = _requestsParseFirestoreValue(v);
          });
          return res;
        }
      }
      return {};
    }
  }

  Future<void> _handleAccept() async {
    setState(() => _isProcessing = true);
    try {
      // 1. FETCH DATA (Hybrid)
      final tData = await _fetchDocData('tenant', widget.tenantUid);
      final lData = await _fetchDocData('landlord', widget.landlordUid);
      final hData = await _fetchDocData('house', widget.landlordUid);

      final String tAadhaar = tData['aadharNumber'] ?? "N/A";
      final String lName = lData['fullName'] ?? "Landlord";
      final String lAadhaar = lData['aadharNumber'] ?? "N/A";

      final List<dynamic> properties = hData['properties'] ?? [];
      if (widget.propertyIndex >= properties.length) throw "Property not found";

      final propData = properties[widget.propertyIndex];
      // Note: propData is already parsed Map if REST or SDK

      final String panchayat = propData['panchayatName'] ?? "N/A";
      final String blockNo = propData['blockNo'] ?? "N/A";
      final String thandaperNo = propData['thandaperNo'] ?? "N/A";
      final String rentAmount = propData['rent'].toString();
      final String securityAmount = propData['securityAmount'].toString();

      // 2. FETCH IMAGES (Hybrid)
      final Uint8List? tSignBytes = await _fetchImageBytes(
        '${widget.tenantUid}/sign/sign.jpg',
      );
      final Uint8List? lSignBytes = await _fetchImageBytes(
        '${widget.landlordUid}/sign/sign.jpg',
      );
      final Uint8List? tPhotoBytes = await _fetchImageBytes(
        '${widget.tenantUid}/profile_pic/',
        isListing: true,
      );
      final Uint8List? lPhotoBytes = await _fetchImageBytes(
        '${widget.landlordUid}/profile_pic/',
        isListing: true,
      );

      if (tSignBytes == null || lSignBytes == null) {
        throw "Signatures are missing.";
      }

      // 3. GENERATE PDF (Same logic)
      final pdf = pw.Document();
      final pw.MemoryImage tSignImg = pw.MemoryImage(tSignBytes);
      final pw.MemoryImage lSignImg = pw.MemoryImage(lSignBytes);
      final pw.MemoryImage? tPhotoImg = tPhotoBytes != null
          ? pw.MemoryImage(tPhotoBytes)
          : null;
      final pw.MemoryImage? lPhotoImg = lPhotoBytes != null
          ? pw.MemoryImage(lPhotoBytes)
          : null;

      final date = DateTime.now();
      final dateString = "${date.day}/${date.month}/${date.year}";

      pdf.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    "RENTAL AGREEMENT",
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  "This Rental Agreement is made and executed on this $dateString.",
                ),
                pw.SizedBox(height: 15),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            "BETWEEN:",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text("1. $lName (LESSOR/Owner)"),
                          pw.Text("   Aadhaar No: $lAadhaar"),
                          pw.SizedBox(height: 10),
                          pw.Text(
                            "AND",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text("2. ${widget.tenantName} (LESSEE/Tenant)"),
                          pw.Text("   Aadhaar No: $tAadhaar"),
                        ],
                      ),
                    ),
                    pw.Column(
                      children: [
                        if (lPhotoImg != null)
                          pw.Container(
                            width: 60,
                            height: 60,
                            child: pw.Image(lPhotoImg, fit: pw.BoxFit.cover),
                          )
                        else
                          pw.Container(
                            width: 60,
                            height: 60,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(),
                            ),
                            child: pw.Center(child: pw.Text("Owner")),
                          ),
                        pw.Text(
                          "Owner",
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.SizedBox(height: 10),
                        if (tPhotoImg != null)
                          pw.Container(
                            width: 60,
                            height: 60,
                            child: pw.Image(tPhotoImg, fit: pw.BoxFit.cover),
                          )
                        else
                          pw.Container(
                            width: 60,
                            height: 60,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(),
                            ),
                            child: pw.Center(child: pw.Text("Tenant")),
                          ),
                        pw.Text(
                          "Tenant",
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  "WHEREAS:",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  "The Lessor is the absolute owner of the residential building situated within the limits of $panchayat, bearing Block No: $blockNo and Thandaper No: $thandaperNo.",
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  "The Lessee has approached the Lessor to take the said schedule building on rent.",
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  "TERMS AND CONDITIONS:",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Bullet(
                  text:
                      "Rent Amount: The monthly rent is fixed at Rs. $rentAmount.",
                ),
                pw.SizedBox(height: 5),
                pw.Bullet(
                  text:
                      "Security Deposit: The Lessee has paid a sum of Rs. $securityAmount.",
                ),
                pw.SizedBox(height: 5),
                pw.Bullet(
                  text:
                      "Period of Tenancy: The tenancy is for a period of 11 months from $dateString.",
                ),
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      children: [
                        pw.Container(
                          width: 80,
                          height: 40,
                          child: pw.Image(lSignImg, fit: pw.BoxFit.contain),
                        ),
                        pw.Text("____________________"),
                        pw.Text("LESSOR (Owner)"),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Container(
                          width: 80,
                          height: 40,
                          child: pw.Image(tSignImg, fit: pw.BoxFit.contain),
                        ),
                        pw.Text("____________________"),
                        pw.Text("LESSEE (Tenant)"),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      // 4. UPLOAD PDF (Hybrid)
      final Uint8List pdfBytes = await pdf.save();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = "agreement_$timestamp.pdf";

      await _uploadPdf(pdfBytes, 'lagreement/${widget.landlordUid}/$fileName');
      await _uploadPdf(pdfBytes, 'tagreement/${widget.tenantUid}/$fileName');

      // 5. UPDATE FIRESTORE (Hybrid)
      // LRequests
      final lReqsMap = await _fetchDocData('lrequests', widget.landlordUid);
      List<dynamic> lReqList = lReqsMap['requests'] ?? [];
      if (widget.requestIndex < lReqList.length) {
        lReqList[widget.requestIndex]['status'] = 'accepted';
        await _updateRequestStatus('lrequests', widget.landlordUid, lReqList);
      }

      // TRequests
      final tReqsMap = await _fetchDocData('trequests', widget.tenantUid);
      List<dynamic> tReqList = tReqsMap['requests'] ?? [];
      for (var req in tReqList) {
        if (req['luid'] == widget.landlordUid &&
            req['propertyIndex'] == widget.propertyIndex &&
            req['status'] == 'pending') {
          req['status'] = 'accepted';
          break;
        }
      }
      await _updateRequestStatus('trequests', widget.tenantUid, tReqList);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Rental Agreement Generated & Signed!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleReject() async {
    setState(() => _isProcessing = true);
    try {
      // Hybrid logic for rejection is just status update
      // LRequests
      final lReqsMap = await _fetchDocData('lrequests', widget.landlordUid);
      List<dynamic> lReqList = lReqsMap['requests'] ?? [];
      if (widget.requestIndex < lReqList.length) {
        lReqList[widget.requestIndex]['status'] = 'rejected';
        await _updateRequestStatus('lrequests', widget.landlordUid, lReqList);
      }

      // TRequests
      final tReqsMap = await _fetchDocData('trequests', widget.tenantUid);
      List<dynamic> tReqList = tReqsMap['requests'] ?? [];
      for (var req in tReqList) {
        if (req['luid'] == widget.landlordUid &&
            req['propertyIndex'] == widget.propertyIndex &&
            req['status'] == 'pending') {
          req['status'] = 'rejected';
          break;
        }
      }
      await _updateRequestStatus('trequests', widget.tenantUid, tReqList);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Request Rejected"),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    onBack: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 40),
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: _profilePicUrl != null
                        ? NetworkImage(_profilePicUrl!)
                        : null,
                    child: _isLoadingImg
                        ? const CircularProgressIndicator()
                        : (_profilePicUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.white,
                                )
                              : null),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.tenantName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _apartmentName != null
                        ? "Applied for: $_apartmentName"
                        : "Loading property details...",
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 30),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "User Documents",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_isLoadingDocs)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  else if (_userDocs.isEmpty)
                    const Text(
                      "No documents uploaded.",
                      style: TextStyle(color: Colors.white54),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        children: _userDocs.map((ref) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.description,
                                color: Colors.blueAccent,
                              ),
                              title: Text(
                                ref.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                              trailing: const Icon(
                                Icons.open_in_new,
                                color: Colors.white54,
                              ),
                              onTap: () => _openDocument(ref),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 30),
                  if (_isProcessing)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 20,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _handleReject,
                              child: const Text(
                                "Decline",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _handleAccept,
                              child: const Text(
                                "Accept",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
              color: Colors.white.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
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
                          color: Colors.white.withValues(alpha: 0.5 * opacity),
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

class AgreementsPage extends StatefulWidget {
  final VoidCallback onBack;
  const AgreementsPage({super.key, required this.onBack});

  @override
  State<AgreementsPage> createState() => _AgreementsPageState();
}

class _AgreementsPageState extends State<AgreementsPage> {
  final String _currentUid = uid;
  List<Reference> _agreementFiles = [];
  bool _isLoading = true;
  String? _error;

  // Helper to determine platform
  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _fetchAgreements();
  }

  Future<void> _fetchAgreements() async {
    if (_currentUid.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = "User not logged in.";
      });
      return;
    }

    try {
      // 1. SDK LOGIC (Android/iOS)
      if (useNativeSdk) {
        // Path: lagreement / [LandlordUID] /
        final storageRef = FirebaseStorage.instance.ref(
          'lagreement/$_currentUid/',
        );
        final listResult = await storageRef.listAll();

        if (mounted) {
          setState(() {
            _agreementFiles = listResult.items;
            _isLoading = false;
          });
        }
      }
      // 2. REST LOGIC (Web/Windows/MacOS/Linux)
      else {
        final String prefix = 'lagreement/$_currentUid/';
        final String encodedPrefix = Uri.encodeComponent(prefix);

        final url = Uri.parse(
          '$kStorageBaseUrl?prefix=$encodedPrefix&key=$kFirebaseAPIKey',
        );

        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List<Reference> mappedRefs = [];

          if (data['items'] != null) {
            for (var item in data['items']) {
              String fullPath = item['name']; // "lagreement/uid/file.pdf"
              String fileName = fullPath.split('/').last; // "file.pdf"

              if (fileName.isNotEmpty) {
                // Use RestReference to match the Reference interface
                mappedRefs.add(
                  RestReferences(name: fileName, fullPath: fullPath)
                      as Reference,
                );
              }
            }
          }

          if (mounted) {
            setState(() {
              _agreementFiles = mappedRefs;
              _isLoading = false;
            });
          }
        } else {
          // Handle empty folder or 404 (bucket logic)
          if (mounted) {
            setState(() {
              _agreementFiles = [];
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      //print("Error fetching agreements: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load agreements.";
        });
      }
    }
  }

  Future<void> _openPdf(Reference ref) async {
    try {
      final String url = await ref.getDownloadURL();
      final Uri uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch PDF viewer")),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error opening file: $e")));
    }
  }

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
                  onBack: widget.onBack,
                ),

                // Screen Title
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Agreements List",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Content Area
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        )
                      : _agreementFiles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 50,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "No agreements found.",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _agreementFiles.length,
                          itemBuilder: (context, index) {
                            final file = _agreementFiles[index];
                            // Format filename (remove extension for cleaner look)
                            final name = file.name
                                .replaceAll('.pdf', '')
                                .replaceAll('_', ' ');

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.redAccent,
                                  size: 30,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.visibility,
                                  color: Colors.white54,
                                ),
                                onTap: () => _openPdf(file),
                              ),
                            );
                          },
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

// --- HELPER CLASS: REST REFERENCE ---
// This acts as a mock Reference for non-mobile platforms
class RestReferences implements Reference {
  @override
  final String name;
  @override
  final String fullPath;

  RestReferences({required this.name, required this.fullPath});

  @override
  Future<String> getDownloadURL() async {
    String encodedName = Uri.encodeComponent(fullPath);
    return '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
  }

  @override
  String get bucket => kStorageBucket;

  // Unused implementations required by interface
  @override
  FirebaseStorage get storage => throw UnimplementedError();
  @override
  Reference get root => throw UnimplementedError();
  @override
  Reference get parent => throw UnimplementedError();
  @override
  Reference child(String path) => throw UnimplementedError();
  @override
  Future<void> delete() => throw UnimplementedError();
  @override
  Future<FullMetadata> getMetadata() => throw UnimplementedError();
  @override
  Future<ListResult> list([ListOptions? options]) => throw UnimplementedError();
  @override
  Future<ListResult> listAll() => throw UnimplementedError();
  @override
  Future<Uint8List?> getData([int maxDownloadSizeBytes = 10485760]) =>
      throw UnimplementedError();
  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  UploadTask putBlob(dynamic blob, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  UploadTask putFile(File file, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  Future<FullMetadata> updateMetadata(SettableMetadata metadata) =>
      throw UnimplementedError();
  @override
  UploadTask putString(
    String data, {
    PutStringFormat format = PutStringFormat.raw,
    SettableMetadata? metadata,
  }) => throw UnimplementedError();
  @override
  DownloadTask writeToFile(File file) => throw UnimplementedError();
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
  //final TextEditingController _amountController = TextEditingController();

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
                              color: Colors.white.withValues(alpha: 0.9),
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
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
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
                                    color: Colors.white.withValues(alpha: 0.7),
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

  // -------------------- PAYMENT FIELDS --------------------
  /*Widget _buildPaymentFields(String method) {
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
  }*/

  // -------------------- SHARED INPUTS --------------------
  /* Widget _textField(String hint, {bool obscure = false}) {
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
  }*/

  /*Widget _amountField() {
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
  }*/

  /*Widget _proceedButton() {
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
  }*/
}

class LandlordsearchProfilePage extends StatefulWidget {
  final String landlordUid; // Landlord's UID from search
  final Map<String, dynamic> propertyDetails; // Specific property details
  final int propertyIndex; // Index of the property

  const LandlordsearchProfilePage({
    super.key,
    required this.landlordUid,
    required this.propertyDetails,
    required this.propertyIndex,
  });

  @override
  LandlordsearchProfilePageState createState() =>
      LandlordsearchProfilePageState();
}

class LandlordsearchProfilePageState extends State<LandlordsearchProfilePage> {
  String? _landlordName;
  String? _landlordPhoneNumber;
  String? _landlordEmail;
  String? _landlordProfilePicUrl;
  List<String> _propertyImageUrls = []; // To store fetched image URLs

  // --- NEW: Variables for Property Documents ---
  List<Reference> _propertyDocs = [];
  bool _isLoadingDocs = true;
  String? _docError;
  // -------------------------------------------

  bool _isLoading = true; // Loading state for main data

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
    _fetchPropertyDocuments(); // Call the new function
  }

  // --- NEW: Function to Fetch Property Documents ---
  Future<void> _fetchPropertyDocuments() async {
    String propertyFolderName = 'property${widget.propertyIndex + 1}';
    String docPath = '${widget.landlordUid}/$propertyFolderName/';

    // 1. SDK LOGIC (Android/iOS)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final storageRef = FirebaseStorage.instance.ref().child(docPath);
        final listResult = await storageRef.listAll();

        // items contains files, prefixes contains folders (like 'images')
        // We only want files in the root of property(n+1)
        if (mounted) {
          setState(() {
            _propertyDocs = listResult.items;
            _isLoadingDocs = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _docError = "Error accessing files";
            _isLoadingDocs = false;
          });
        }
      }
    }
    // 2. REST LOGIC (Web/Desktop)
    else {
      try {
        // CRITICAL FIX: Added 'delimiter=/' to prevent listing files inside subfolders (like images/)
        final listUrl = Uri.parse(
          '$kStorageBaseUrl?prefix=$docPath&delimiter=/&key=$kFirebaseAPIKey',
        );
        final response = await http.get(listUrl);

        List<Reference> mappedRefs = [];
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // 'items' contains files in the current folder
          // 'prefixes' contains subfolders (like images/), which we ignore here
          if (data['items'] != null) {
            for (var item in data['items']) {
              String fullPath = item['name'];
              String fileName = fullPath.split('/').last;

              if (fileName.isNotEmpty) {
                mappedRefs.add(
                  RestReference(name: fileName, fullPath: fullPath)
                      as Reference,
                );
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _propertyDocs = mappedRefs;
            _isLoadingDocs = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _docError = "Error accessing files";
            _isLoadingDocs = false;
          });
        }
      }
    }
  }

  // --- NEW: Helper to Open Document ---
  Future<void> _openDocument(Reference ref) async {
    try {
      String url = await ref.getDownloadURL();
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open document")),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error opening file: $e")));
    }
  }

  Future<void> _fetchData() async {
    try {
      // SDK LOGIC (Android/iOS)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // 1. Fetch Landlord Details
        DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
            .collection('landlord')
            .doc(widget.landlordUid)
            .get();

        if (landlordDoc.exists && mounted) {
          var data = landlordDoc.data() as Map<String, dynamic>?;
          if (data != null) {
            setState(() {
              _landlordName =
                  data['fullName'] as String? ?? 'Name Not Available';
              _landlordPhoneNumber = data['phoneNumber'] as String?;
              _landlordEmail = data['email'] as String?;
            });
          } else {
            if (mounted) {
              setState(() => _landlordName = 'Landlord Data Not Found');
            }
          }
        } else {
          if (mounted) setState(() => _landlordName = 'Landlord Not Found');
        }

        // 2. Fetch Landlord Profile Pic
        try {
          ListResult profilePicResult = await FirebaseStorage.instance
              .ref('${widget.landlordUid}/profile_pic/')
              .list(const ListOptions(maxResults: 1));
          if (profilePicResult.items.isNotEmpty && mounted) {
            String url = await profilePicResult.items.first.getDownloadURL();
            setState(() {
              _landlordProfilePicUrl = url;
            });
          }
        } catch (storageError) {
          // Ignore
        }

        // 3. Fetch Property Images
        List<String> imageUrls = [];
        String propertyFolderName = 'property${widget.propertyIndex + 1}';
        String imageFolderPath =
            '${widget.landlordUid}/$propertyFolderName/images/';
        try {
          ListResult imageListResult = await FirebaseStorage.instance
              .ref(imageFolderPath)
              .listAll();
          for (var item in imageListResult.items) {
            String url = await item.getDownloadURL();
            imageUrls.add(url);
          }
          if (mounted) {
            setState(() {
              _propertyImageUrls = imageUrls;
            });
          }
        } catch (storageError) {
          // Ignore
        }
      }
      // REST LOGIC (Web/Desktop)
      else {
        // 1. Fetch Landlord Details
        final landlordUrl = Uri.parse(
          '$kFirestoreBaseUrl/landlord/${widget.landlordUid}?key=$kFirebaseAPIKey',
        );
        final landlordResponse = await http.get(landlordUrl);
        if (landlordResponse.statusCode == 200) {
          final data = jsonDecode(landlordResponse.body);
          if (data['fields'] != null) {
            final fields = data['fields'];
            setState(() {
              _landlordName =
                  fields['fullName']?['stringValue'] ?? 'Name Not Available';
              _landlordPhoneNumber = fields['phoneNumber']?['stringValue'];
              _landlordEmail = fields['email']?['stringValue'];
            });
          }
        }

        // 2. Fetch Profile Pic
        final profilePicListUrl = Uri.parse(
          '$kStorageBaseUrl?prefix=${widget.landlordUid}/profile_pic/&key=$kFirebaseAPIKey',
        );
        final profileResponse = await http.get(profilePicListUrl);
        if (profileResponse.statusCode == 200) {
          final data = jsonDecode(profileResponse.body);
          if (data['items'] != null && (data['items'] as List).isNotEmpty) {
            String objectName = data['items'][0]['name'];
            String encodedName = Uri.encodeComponent(objectName);
            String url =
                '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
            if (mounted) {
              setState(() {
                _landlordProfilePicUrl = url;
              });
            }
          }
        }

        // 3. Fetch Property Images
        String propertyFolderName = 'property${widget.propertyIndex + 1}';
        String imageFolderPath =
            '${widget.landlordUid}/$propertyFolderName/images/';
        final imageListUrl = Uri.parse(
          '$kStorageBaseUrl?prefix=$imageFolderPath&key=$kFirebaseAPIKey',
        );
        final imageResponse = await http.get(imageListUrl);
        if (imageResponse.statusCode == 200) {
          final data = jsonDecode(imageResponse.body);
          List<String> imageUrls = [];
          if (data['items'] != null) {
            for (var item in data['items']) {
              String objectName = item['name'];
              String encodedName = Uri.encodeComponent(objectName);
              String url =
                  '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
              imageUrls.add(url);
            }
          }
          if (mounted) {
            setState(() {
              _propertyImageUrls = imageUrls;
            });
          }
        }
      }
    } catch (e) {
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
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- NEW: Handle Send Request Logic ---
  Future<void> _handleSendRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must be logged in to send a request."),
        ),
      );
      return;
    }

    try {
      String timestamp = DateTime.now().toIso8601String();
      String aptName =
          widget.propertyDetails['apartmentName'] ?? 'My Apartment';

      // Request Data Maps
      Map<String, dynamic> tRequestData = {
        'luid': widget.landlordUid,
        'tuid': user.uid,
        'landlordName': _landlordName ?? 'Unknown',
        'status': 'pending',
        'propertyIndex': widget.propertyIndex,
        'timestamp': timestamp,
        'apartmentName': aptName,
      };

      Map<String, dynamic> lRequestData = {
        'tuid': user.uid,
        'propertyIndex': widget.propertyIndex,
        'timestamp': timestamp,
        'status': 'pending',
        'apartmentName': aptName,
      };

      // 1. SDK LOGIC
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await FirebaseFirestore.instance
            .collection('trequests')
            .doc(user.uid)
            .set({
              'requests': FieldValue.arrayUnion([tRequestData]),
              'tenantUid': user.uid,
            }, SetOptions(merge: true));

        await FirebaseFirestore.instance
            .collection('lrequests')
            .doc(widget.landlordUid)
            .set({
              'requests': FieldValue.arrayUnion([lRequestData]),
              'landlordUid': widget.landlordUid,
            }, SetOptions(merge: true));
      }
      // 2. REST LOGIC
      else {
        Future<void> updateRequestsRest(
          String collection,
          String docId,
          Map<String, dynamic> newRequest,
          String uidField,
        ) async {
          final url = Uri.parse(
            '$kFirestoreBaseUrl/$collection/$docId?key=$kFirebaseAPIKey',
          );

          // Get existing requests to append (Read-Modify-Write)
          List<Map<String, dynamic>> currentRequests = [];
          try {
            final getResponse = await http.get(url);
            if (getResponse.statusCode == 200) {
              final data = jsonDecode(getResponse.body);
              if (data['fields'] != null &&
                  data['fields']['requests'] != null) {
                var rawList =
                    data['fields']['requests']['arrayValue']['values'] as List?;
                if (rawList != null) {
                  for (var item in rawList) {
                    if (item['mapValue'] != null &&
                        item['mapValue']['fields'] != null) {
                      Map<String, dynamic> cleanMap = {};
                      item['mapValue']['fields'].forEach((key, val) {
                        cleanMap[key] = _parseFirestoreRestValue(val);
                      });
                      currentRequests.add(cleanMap);
                    }
                  }
                }
              }
            }
          } catch (_) {}

          currentRequests.add(newRequest);

          List<Map<String, dynamic>> jsonValues = currentRequests
              .map((p) => _encodeMapForFirestore(p))
              .toList();

          Map<String, dynamic> body = {
            "fields": {
              "requests": {
                "arrayValue": {"values": jsonValues},
              },
              uidField: {"stringValue": docId},
            },
          };

          await http.patch(
            url,
            body: jsonEncode(body),
            headers: {"Content-Type": "application/json"},
          );
        }

        await updateRequestsRest(
          'trequests',
          user.uid,
          tRequestData,
          'tenantUid',
        );
        await updateRequestsRest(
          'lrequests',
          widget.landlordUid,
          lRequestData,
          'landlordUid',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request sent to the landlord!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to send request: $e")));
      }
    }
  }

  // Helper to convert Dart Map to Firestore JSON for REST
  Map<String, dynamic> _encodeMapForFirestore(Map<String, dynamic> map) {
    Map<String, dynamic> fields = {};
    map.forEach((k, v) {
      if (v == null) return;
      if (v is String) {
        fields[k] = {"stringValue": v};
      } else if (v is int) {
        fields[k] = {"integerValue": v.toString()};
      } else if (v is double) {
        fields[k] = {"doubleValue": v.toString()};
      } else if (v is bool) {
        fields[k] = {"booleanValue": v};
      } else if (v is List) {
        fields[k] = {
          "arrayValue": {
            "values": v.map((e) => {"stringValue": e.toString()}).toList(),
          },
        };
      }
    });
    return {
      "mapValue": {"fields": fields},
    };
  }

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
                CustomTopNavBar(
                  showBack: true,
                  title: "Landlord Profile",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 20),

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
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 50,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.3,
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
                                      _landlordName ?? "...",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      widget.propertyDetails['location'] ??
                                          "Location Unknown",
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 25),

                              // ---------- Send Request Button ----------
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _handleSendRequest, // UPDATED LOGIC
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
                              const SizedBox(height: 25),

                              // ---------- Property Photos ----------
                              const Text(
                                "Property Photos",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 140,
                                child: _propertyImageUrls.isEmpty
                                    ? Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Center(
                                          child: const Icon(
                                            Icons.hide_image_outlined,
                                            color: Colors.white70,
                                            size: 40,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _propertyImageUrls.length,
                                        itemBuilder: (context, index) {
                                          return GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => Scaffold(
                                                    backgroundColor:
                                                        Colors.black,
                                                    appBar: AppBar(
                                                      backgroundColor:
                                                          Colors.black,
                                                      iconTheme:
                                                          const IconThemeData(
                                                            color: Colors.white,
                                                          ),
                                                    ),
                                                    body: Center(
                                                      child: InteractiveViewer(
                                                        panEnabled: true,
                                                        minScale: 0.5,
                                                        maxScale: 4.0,
                                                        child: Image.network(
                                                          _propertyImageUrls[index],
                                                          fit: BoxFit.contain,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              width: 160,
                                              margin: const EdgeInsets.only(
                                                right: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                image: DecorationImage(
                                                  image: NetworkImage(
                                                    _propertyImageUrls[index],
                                                  ),
                                                  fit: BoxFit.cover,
                                                  onError:
                                                      (exception, stackTrace) {
                                                        //print(
                                                        //"Error loading image",
                                                        //);
                                                      },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(height: 25),

                              // ---------- NEW: Property Documents Section ----------
                              const Text(
                                "Property Document",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_isLoadingDocs)
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              else if (_docError != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.redAccent),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.redAccent,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _docError!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (_propertyDocs.isEmpty)
                                const Text(
                                  "No documents available.",
                                  style: TextStyle(color: Colors.white54),
                                )
                              else
                                Column(
                                  children: _propertyDocs.map((ref) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.description_outlined,
                                          color: Colors.blueAccent,
                                        ),
                                        title: Text(
                                          ref.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.open_in_new,
                                          color: Colors.white54,
                                          size: 20,
                                        ),
                                        onTap: () => _openDocument(ref),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              const SizedBox(height: 30),
                              // -----------------------------------------------------

                              // ---------- About Property ----------
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
                                  "Rent: ₹${widget.propertyDetails['rent'] ?? 'N/A'} / month",
                                ),
                                _infoRow(
                                  Icons.security,
                                  "Security: ₹${widget.propertyDetails['securityAmount'] ?? 'N/A'}",
                                ),
                                _infoRow(
                                  Icons.people,
                                  "Max Occupancy: ${widget.propertyDetails['maxOccupancy'] ?? 'N/A'}",
                                ),
                                // --- NEW FIELDS ---
                                _infoRow(
                                  Icons.location_city,
                                  "Panchayat: ${widget.propertyDetails['panchayatName'] ?? 'N/A'}",
                                ),
                                _infoRow(
                                  Icons.map,
                                  "Block No: ${widget.propertyDetails['blockNo'] ?? 'N/A'}",
                                ),
                                _infoRow(
                                  Icons.confirmation_number,
                                  "Thandaper No: ${widget.propertyDetails['thandaperNo'] ?? 'N/A'}",
                                ),
                              ]),
                              const SizedBox(height: 25),

                              // ---------- Contact Section ----------
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
                              const SizedBox(height: 25),

                              // ---------- Write a Review Button ----------
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
                              const SizedBox(height: 35),

                              // ---------- Reviews Section ----------
                              const Text(
                                "Reviews",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...dummyReviews.map((review) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: Colors.orange
                                                .withValues(alpha: 0.8),
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
                              }),
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
    );
  }

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
        color: Colors.white.withValues(alpha: 0.1),
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

  void _showReviewDialog(BuildContext context) {
    final TextEditingController reviewController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Write a Review",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: reviewController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Enter your review here...",
            hintStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Review submitted: ${reviewController.text}"),
                ),
              );
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
}

class LandlordsearchProfilePage2 extends StatefulWidget {
  final String landlordUid; // Landlord's UID from search
  final Map<String, dynamic> propertyDetails; // Specific property details
  final int propertyIndex; // Index of the property for image path

  const LandlordsearchProfilePage2({
    super.key,
    required this.landlordUid,
    required this.propertyDetails,
    required this.propertyIndex,
  });

  @override
  LandlordsearchProfilePage2State createState() =>
      LandlordsearchProfilePage2State();
}

class LandlordsearchProfilePage2State
    extends State<LandlordsearchProfilePage2> {
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
      //print(
      //"Fetching landlord details for UID: ${widget.landlordUid}",
      //); // Debug print
      DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(widget.landlordUid)
          .get();

      if (landlordDoc.exists && mounted) {
        var data = landlordDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          //print("Landlord data found: $data"); // Debug print
          setState(() {
            _landlordName = data['fullName'] as String? ?? 'Name Not Available';
            _landlordPhoneNumber = data['phoneNumber'] as String?;
            _landlordEmail = data['email'] as String?;
            // Assuming profile pic URL isn't stored in landlord doc, fetch from storage next
          });
        } else {
          //print("Landlord document data is null."); // Debug print
          if (mounted) {
            setState(() => _landlordName = 'Landlord Data Not Found');
          }
        }
      } else {
        //print(
        //"Landlord document not found for UID: ${widget.landlordUid}",
        //); // Debug print
        if (mounted) setState(() => _landlordName = 'Landlord Not Found');
      }

      // 2. Fetch Landlord Profile Pic from Storage
      //print("Fetching landlord profile picture..."); // Debug print
      try {
        ListResult profilePicResult = await FirebaseStorage.instance
            .ref('${widget.landlordUid}/profile_pic/')
            .list(const ListOptions(maxResults: 1));
        if (profilePicResult.items.isNotEmpty && mounted) {
          String url = await profilePicResult.items.first.getDownloadURL();
          //print("Profile picture URL fetched: $url"); // Debug print
          setState(() {
            _landlordProfilePicUrl = url;
          });
        } else {
          //print("No profile picture found in storage."); // Debug print
        }
      } catch (storageError) {
        //print(
        //"Error fetching landlord profile pic: $storageError",
        //); // Keep default icon
      }

      // 3. Fetch Property Images from Storage
      List<String> imageUrls = [];
      String propertyFolderName =
          'property${widget.propertyIndex + 1}'; // property1, property2 etc.
      String imageFolderPath =
          '${widget.landlordUid}/$propertyFolderName/images/';
      //print("Fetching property images from: $imageFolderPath"); // Debug print
      try {
        ListResult imageListResult = await FirebaseStorage.instance
            .ref(imageFolderPath)
            .listAll();
        //print(
        //"Found ${imageListResult.items.length} images in storage.",
        //); // Debug print
        for (var item in imageListResult.items) {
          String url = await item.getDownloadURL();
          imageUrls.add(url);
        }
        if (mounted) {
          //print(
          //"Setting ${imageUrls.length} property image URLs.",
          //); // Debug print
          setState(() {
            _propertyImageUrls = imageUrls;
          });
        }
      } catch (storageError) {
        //print(
        //"Error fetching property images from $imageFolderPath: $storageError",
        //); // Will show placeholders
      }
    } catch (e) {
      //print("Error fetching landlord/property data: $e");
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
        //print(
        //"Finished fetching data, setting isLoading = false.",
        //); // Debug print
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget infoContainer(String title, List<Widget> children) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
    }

    Widget infoRow(IconData icon, String text) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: Colors.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      );
    }

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
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.3,
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
                                          "Location Unknown",
                                      // Fetch from passed details
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 25),

                              // Keep spacing
                              // ---------- Send Request Button (Keep original) ----------
                              const SizedBox(height: 25),
                              // Keep spacing
                              // ---------- Property Photos ----------
                              const Text(
                                "Property Photos",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              // Keep style
                              const SizedBox(height: 10),
                              // Keep spacing
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
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
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
                                              color: Colors.white.withValues(
                                                alpha: 0.2,
                                              ), // Background while loading
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              image: DecorationImage(
                                                image: NetworkImage(
                                                  _propertyImageUrls[index],
                                                ),
                                                // Use NetworkImage
                                                fit: BoxFit.cover,
                                                // Optional: Add error builder for NetworkImage
                                                onError: (exception, stackTrace) {
                                                  //print(
                                                  //"Error loading image URL ${_propertyImageUrls[index]}: $exception",
                                                  //);
                                                  // Optionally return a placeholder widget here too
                                                },
                                              ),
                                            ),
                                            // Removed overlay icon from original example
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(height: 30),
                              // Keep spacing
                              // ---------- About Property (Display fetched data) ----------
                              infoContainer("About Property", [
                                infoRow(
                                  Icons.home,
                                  widget.propertyDetails['roomType'] ?? 'N/A',
                                ),
                                infoRow(
                                  Icons.location_on,
                                  widget.propertyDetails['location'] ?? 'N/A',
                                ),
                                infoRow(
                                  Icons.attach_money,
                                  "₹${widget.propertyDetails['rent'] ?? 'N/A'} / month",
                                ),
                                infoRow(
                                  Icons.people,
                                  "Max Occupancy: ${widget.propertyDetails['maxOccupancy'] ?? 'N/A'}",
                                ), // Slightly clearer text
                              ]),
                              const SizedBox(height: 25),
                              // Keep spacing
                              // ---------- Contact Section (Display fetched data) ----------
                              infoContainer("Contact Details", [
                                infoRow(
                                  Icons.phone,
                                  _landlordPhoneNumber ?? 'Not Available',
                                ),
                                infoRow(
                                  Icons.email,
                                  _landlordEmail ?? 'Not Available',
                                ),
                              ]),
                              const SizedBox(height: 25),

                              // Keep spacing
                              const SizedBox(height: 35),
                              // Keep spacing
                              // ---------- Reviews Section (Keep original dummy data) ----------
                              const Text(
                                "Reviews",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              // Keep style
                              const SizedBox(height: 10),
                              // Keep spacing
                              ...dummyReviews.map((review) {
                                // Keep original review display structure
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
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
                                                .withValues(alpha: 0.8),
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
                              }),
                              const SizedBox(height: 40),
                              // Keep spacing
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
}
