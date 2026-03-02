import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:main_project/config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

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

  double? latitude;
  double? longitude;

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

  // --- NEW: Aadhar Verification State ---
  bool _isAadharVerified = false;

  List<LandlordPropertyForm> propertyCards = [
    LandlordPropertyForm(documents: [DocumentFields()]),
  ];
  bool _isUploading = false;

  List<Map<String, dynamic>> _myApartments = [];
  bool _isLoadingApartments = true;

  String? _landlordName;
  String? _profilePicUrl;

  final List<String> propertyDocOptions = [
    "Property Tax Receipt",
    "Land Ownership Proof",
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchLandlordData();
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

  Future<void> _fetchLandlordData() async {
    final String userUid = uid;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('landlord')
            .doc(userUid)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _landlordName = data['fullName'];
            _isAadharVerified = data['aadhar'] == 'verified';
          });
        }
        final ref = FirebaseStorage.instance.ref('$userUid/profile_pic/');
        final list = await ref.list(const ListOptions(maxResults: 1));
        if (list.items.isNotEmpty) {
          String url = await list.items.first.getDownloadURL();
          if (mounted) setState(() => _profilePicUrl = url);
        }
      } catch (_) {}
    } else {
      try {
        final firestoreUrl = Uri.parse(
          '$kFirestoreBaseUrl/landlord/$userUid?key=$kFirebaseAPIKey',
        );
        final fsResponse = await http.get(firestoreUrl);
        if (fsResponse.statusCode == 200) {
          final data = jsonDecode(fsResponse.body);
          if (data['fields'] != null) {
            setState(() {
              if (data['fields']['fullName'] != null) {
                _landlordName = data['fields']['fullName']['stringValue'];
              }
              if (data['fields']['aadhar'] != null) {
                _isAadharVerified =
                    data['fields']['aadhar']['stringValue'] == 'verified';
              }
            });
          }
        }
        final storageListUrl = Uri.parse(
          '$kStorageBaseUrl?prefix=$userUid/profile_pic/&key=$kFirebaseAPIKey',
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

  Future<void> _fetchMyApartments() async {
    final String userUid = uid;

    if ((kIsWeb) || (Platform.isAndroid || Platform.isIOS)) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('house')
            .doc(userUid)
            .get();
        if (doc.exists && mounted) {
          Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('properties')) {
            List<Map<String, dynamic>> rawList =
                List<Map<String, dynamic>>.from(data['properties']);

            setState(() {
              _myApartments = rawList;
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
          '$kFirestoreBaseUrl/house/$userUid?key=$kFirebaseAPIKey',
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
            if (!Platform.isAndroid && !Platform.isIOS) {
              fileBytes = await fileMobile.readAsBytes();
            }
          }
        }
      } else if (fileInput is XFile) {
        extension = fileInput.name.split('.').last;
        if (kIsWeb) {
          fileBytes = await fileInput.readAsBytes();
        } else {
          fileMobile = File(fileInput.path);
          if (!Platform.isAndroid && !Platform.isIOS) {
            fileBytes = await fileMobile.readAsBytes();
          }
        }
      }
    } catch (e) {
      return null;
    }

    String fullFileName = '$fileNameWithoutExt.$extension';

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
    } else {
      if (fileBytes == null) return null;
      try {
        String fullPath = '$folderPath/$fullFileName';
        String encodedPath = Uri.encodeComponent(fullPath);

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

  Future<void> _openFile(String url) async {
    try {
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
    int maxIndex = -1;
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

            // 2. Save to Firestore (Your existing logic)
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              await FirebaseFirestore.instance
                  .collection('landlord')
                  .doc(userUid)
                  .update({'aadhar': 'verified'});
            } else {
              final url = Uri.parse(
                '$kFirestoreBaseUrl/landlord/$userUid?updateMask.fieldPaths=aadhar&key=$kFirebaseAPIKey',
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

  Future<LatLng?> _pickLocationOnMap() async {
    LatLng picked = const LatLng(9.9312, 76.2673);

    // Controller to move the map programmatically
    final MapController mapController = MapController();
    // Controller for the search input field
    final TextEditingController searchController = TextEditingController();

    return showDialog<LatLng>(
      context: context,
      builder: (dialogContext) {
        LatLng tempPicked = picked;
        bool isSearching = false;

        return StatefulBuilder(
          builder: (stfContext, setState) {
            // Function to handle the search API call
            Future<void> searchPlace() async {
              final query = searchController.text.trim();
              if (query.isEmpty) return;

              setState(() => isSearching = true);

              try {
                // Using OpenStreetMap's free Nominatim API for geocoding
                final url = Uri.parse(
                  'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1',
                );

                final response = await http.get(
                  url,
                  headers: {
                    // Nominatim requires a valid User-Agent per their terms of service
                    'User-Agent': 'com.securehomes.rental_project',
                  },
                );

                if (response.statusCode == 200) {
                  final data = json.decode(response.body) as List;
                  if (data.isNotEmpty) {
                    // Extract coordinates
                    final lat = double.parse(data[0]['lat']);
                    final lon = double.parse(data[0]['lon']);
                    final newPoint = LatLng(lat, lon);

                    setState(() {
                      tempPicked = newPoint;
                    });

                    // Move the map to the new location
                    mapController.move(newPoint, 14.0);
                  } else {
                    if (stfContext.mounted) {
                      ScaffoldMessenger.of(stfContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Place not found. Try a different search term.",
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              } catch (e) {
                if (stfContext.mounted) {
                  ScaffoldMessenger.of(stfContext).showSnackBar(
                    SnackBar(
                      content: Text("Search failed: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                setState(() => isSearching = false);
              }
            }

            return AlertDialog(
              contentPadding: EdgeInsets.zero,
              backgroundColor: const Color(
                0xFF1E2A47,
              ), // Matching your app's theme
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: const BoxDecoration(
                  color: Color(0xFF141E30),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Search location...",
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => searchPlace(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.orange,
                              ),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(
                              Icons.search,
                              color: Colors.orange,
                            ),
                            onPressed: searchPlace,
                          ),
                  ],
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: FlutterMap(
                  mapController: mapController, // Attach the controller
                  options: MapOptions(
                    initialCenter: picked,
                    initialZoom: 13.0,
                    onTap: (_, point) {
                      setState(() {
                        tempPicked = point;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.securehomes.rental_project',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: tempPicked,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  onPressed: () => Navigator.pop(context, tempPicked),
                  child: const Text(
                    "Select This Location",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _uploadNewProperty() async {
    final String userUid = uid;

    for (var card in propertyCards) {
      if (card.apartmentNameController.text.isEmpty ||
          card.roomTypeController.text.isEmpty ||
          card.locationController.text.isEmpty ||
          card.rentController.text.isEmpty ||
          card.maxOccupancyController.text.isEmpty ||
          card.panchayatNameController.text.isEmpty ||
          card.blockNoController.text.isEmpty ||
          card.thandaperNoController.text.isEmpty ||
          card.securityAmountController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("All text fields are mandatory."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (double.tryParse(card.rentController.text) == null ||
          int.tryParse(card.maxOccupancyController.text) == null ||
          double.tryParse(card.securityAmountController.text) == null ||
          int.tryParse(card.blockNoController.text) == null ||
          int.tryParse(card.roomTypeController.text) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Rent, Room Type, Occupancy, Security Amount, and Block No must be valid numbers.",
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (card.houseImages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("At least one property image is required."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      bool hasTax = card.documents.any(
        (d) => d.selectedDoc == "Property Tax Receipt" && d.pickedFile != null,
      );
      bool hasProof = card.documents.any(
        (d) => d.selectedDoc == "Land Ownership Proof" && d.pickedFile != null,
      );

      if (!hasTax || !hasProof) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Both 'Property Tax Receipt' and 'Land Ownership Proof' are mandatory.",
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    LatLng? loc = await _pickLocationOnMap();
    if (loc == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a location on the map."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      List<Map<String, dynamic>> newProps = [];
      int nextFolderNum = _getNextPropertyFolderIndex();

      for (var card in propertyCards) {
        String folderName = 'property$nextFolderNum';
        List<String> docUrls = [];
        List<String> imageUrls = [];

        for (var doc in card.documents) {
          if (doc.selectedDoc != null && doc.pickedFile != null) {
            String? url = await _uploadFileWithReplace(
              doc.pickedFile,
              '$userUid/$folderName',
              doc.selectedDoc!,
            );
            if (url != null) docUrls.add(url);
          }
        }

        for (int i = 0; i < card.houseImages.length; i++) {
          String? url = await _uploadFileWithReplace(
            card.houseImages[i],
            '$userUid/$folderName/images',
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
          'latitude': loc.latitude,
          'longitude': loc.longitude,
          'status': 'active',
        });

        nextFolderNum++;
      }

      if (newProps.isNotEmpty) {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          await FirebaseFirestore.instance.collection('house').doc(userUid).set(
            {'properties': FieldValue.arrayUnion(newProps)},
            SetOptions(merge: true),
          );
        } else {
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

          final url = Uri.parse(
            '$kFirestoreBaseUrl/house/$userUid?key=$kFirebaseAPIKey',
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
        _isUploading = false;
      });
      _fetchMyApartments();
      if (newProps.isNotEmpty) {
        _tabController.animateTo(2);
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteImageFromProperty(
    int propertyIndex,
    int imageIndex,
  ) async {
    final String userUid = uid;

    List<dynamic> currentImages = List.from(
      _myApartments[propertyIndex]['houseImageUrls'] ?? [],
    );
    if (imageIndex >= currentImages.length) return;

    String imageUrlToDelete = currentImages[imageIndex];
    List<dynamic> updatedImages = List.from(currentImages)
      ..removeAt(imageIndex);

    bool confirm =
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: const Color(0xFF1E2A47),
            title: const Text(
              "Delete Image?",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "This cannot be undone.",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
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

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Deleting image...")));

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        Map<String, dynamic> oldProp = _myApartments[propertyIndex];
        Map<String, dynamic> newProp = Map.from(oldProp);
        newProp['houseImageUrls'] = updatedImages;

        await FirebaseFirestore.instance
            .collection('house')
            .doc(userUid)
            .update({
              'properties': FieldValue.arrayRemove([oldProp]),
            });
        await FirebaseFirestore.instance
            .collection('house')
            .doc(userUid)
            .update({
              'properties': FieldValue.arrayUnion([newProp]),
            });

        try {
          await FirebaseStorage.instance.refFromURL(imageUrlToDelete).delete();
        } catch (_) {}

        _fetchMyApartments();
      } catch (_) {}
    } else {
      try {
        _myApartments[propertyIndex]['houseImageUrls'] = updatedImages;

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
          '$kFirestoreBaseUrl/house/$userUid?key=$kFirebaseAPIKey',
        );
        await http.patch(
          url,
          body: jsonEncode(body),
          headers: {"Content-Type": "application/json"},
        );

        try {
          Uri uri = Uri.parse(imageUrlToDelete);
          String pathSegment = uri.path.split('/o/').last;
          final deleteUrl = Uri.parse(
            '$kStorageBaseUrl/$pathSegment?key=$kFirebaseAPIKey',
          );
          await http.delete(deleteUrl);
        } catch (_) {}

        _fetchMyApartments();
      } catch (_) {}
    }
  }

  Future<void> _deleteStorageFolder(String folderPath) async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final list = await FirebaseStorage.instance.ref(folderPath).listAll();
        for (var item in list.items) {
          await item.delete();
        }
        for (var prefix in list.prefixes) {
          await _deleteStorageFolder(prefix.fullPath);
        }
      } catch (e) {
        debugPrint("Error deleting storage folder: $e");
      }
    } else {
      try {
        final encodedPrefix = Uri.encodeComponent(folderPath);
        final listUrl = Uri.parse(
          '$kStorageBaseUrl?prefix=$encodedPrefix&key=$kFirebaseAPIKey',
        );
        final response = await http.get(listUrl);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['items'] != null) {
            for (var item in data['items']) {
              String name = item['name'];
              String encodedName = Uri.encodeComponent(name);
              final delUrl = Uri.parse(
                '$kStorageBaseUrl/$encodedName?key=$kFirebaseAPIKey',
              );
              await http.delete(delUrl);
            }
          }
        }
      } catch (e) {
        debugPrint("Error deleting storage REST: $e");
      }
    }
  }

  Future<void> _deleteApartment(int index) async {
    final String userUid = uid;

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
              "This will PERMANENTLY delete the property and all its files.",
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
    String folderName = prop['folderName'] ?? 'property$index';

    try {
      await _deleteStorageFolder('$userUid/$folderName/');

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await FirebaseFirestore.instance
            .collection('house')
            .doc(userUid)
            .update({
              'properties': FieldValue.arrayRemove([prop]),
            });
      } else {
        List<Map<String, dynamic>> updatedList = List.from(_myApartments)
          ..removeAt(index);

        List<Map<String, dynamic>> jsonValues = updatedList
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
          '$kFirestoreBaseUrl/house/$userUid?key=$kFirebaseAPIKey',
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
          content: Text("Property deleted successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Delete failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoadingApartments = false);
    }
  }

  Future<void> _updateApartmentFiles(int index) async {
    final String userUid = uid;

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
        '$userUid/$folderName/images',
        name,
      );
      if (url != null) newUrls.add(url);
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      List<dynamic> existingUrls = prop['houseImageUrls'] ?? [];
      List<dynamic> updatedUrls = [...existingUrls, ...newUrls];
      await FirebaseFirestore.instance.collection('house').doc(userUid).update({
        'properties': FieldValue.arrayRemove([prop]),
      });
      prop['houseImageUrls'] = updatedUrls;
      await FirebaseFirestore.instance.collection('house').doc(userUid).update({
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
        '$kFirestoreBaseUrl/house/$userUid?key=$kFirebaseAPIKey',
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

  Future<void> _updatePropertyDoc(
    int propIndex,
    int docIndex,
    String currentUrl,
  ) async {
    PlatformFile? file = await _pickDocument();
    if (file == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Updating document...")));

    Map<String, dynamic> prop = _myApartments[propIndex];
    String folderName = prop['folderName'] ?? 'property${propIndex + 1}';

    String docType = "updated_doc_${DateTime.now().millisecondsSinceEpoch}";
    if (docIndex == 0) docType = "Property Tax Receipt";
    if (docIndex == 1) docType = "Land Ownership Proof";

    final String userUid = uid;
    String? newUrl = await _uploadFileWithReplace(
      file,
      '$userUid/$folderName',
      docType,
    );

    if (newUrl != null) {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          await FirebaseStorage.instance.refFromURL(currentUrl).delete();
        } catch (_) {}
      } else {
        try {
          Uri uri = Uri.parse(currentUrl);
          String pathSegment = uri.path.split('/o/').last;
          final deleteUrl = Uri.parse(
            '$kStorageBaseUrl/$pathSegment?key=$kFirebaseAPIKey',
          );
          await http.delete(deleteUrl);
        } catch (_) {}
      }

      List<dynamic> docs = List.from(prop['documentUrls']);
      if (docIndex < docs.length) {
        docs[docIndex] = newUrl;
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await FirebaseFirestore.instance
            .collection('house')
            .doc(userUid)
            .update({
              'properties': FieldValue.arrayRemove([prop]),
            });
        prop['documentUrls'] = docs;
        await FirebaseFirestore.instance
            .collection('house')
            .doc(userUid)
            .update({
              'properties': FieldValue.arrayUnion([prop]),
            });
      } else {
        prop['documentUrls'] = docs;
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
          '$kFirestoreBaseUrl/house/$userUid?key=$kFirebaseAPIKey',
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
          content: Text("Document Updated!"),
          backgroundColor: Colors.green,
        ),
      );
    }
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
            const AnimatedGradientBackground(),
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

  // --- UPDATED: Mock DigiLocker Verification Tab ---
  Widget _buildUserDocsTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Identity Verification",
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
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
                      color: _isAadharVerified ? Colors.green : Colors.orange,
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
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.security, color: Colors.white),
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
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
          List<dynamic> docs = apt['documentUrls'] ?? [];

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
                  ),
                  child: images.isEmpty
                      ? const Center(
                          child: Icon(
                            Icons.home,
                            color: Colors.white54,
                            size: 40,
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length,
                          itemBuilder: (c, imgIndex) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => Scaffold(
                                            backgroundColor: Colors.black,
                                            appBar: AppBar(
                                              backgroundColor: Colors.black,
                                            ),
                                            body: Center(
                                              child: Image.network(
                                                images[imgIndex],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        images[imgIndex],
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: GestureDetector(
                                      onTap: () => _deleteImageFromProperty(
                                        index,
                                        imgIndex,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.delete,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
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
                      if (docs.isNotEmpty) ...[
                        const Text(
                          "Documents:",
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 5),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: docs.length,
                          itemBuilder: (ctx, docIdx) {
                            String url = docs[docIdx];
                            String name = "Doc ${docIdx + 1}";
                            if (url.contains('Property%20Tax')) {
                              name = "Tax Receipt";
                            }
                            if (url.contains('Land%20Ownership')) {
                              name = "Ownership Proof";
                            }

                            return Row(
                              children: [
                                Icon(
                                  Icons.description,
                                  color: Colors.white54,
                                  size: 16,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _openFile(url),
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 12,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _updatePropertyDoc(index, docIdx, url),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size(50, 20),
                                  ),
                                  child: const Text(
                                    "Replace",
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],

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
    int? currentIndex,
    List<DocumentFields>? currentList,
  }) {
    List<String> availableOptions;
    if (currentIndex != null && currentList != null) {
      Set<String> selected = currentList
          .where(
            (e) =>
                e.selectedDoc != null && currentList.indexOf(e) != currentIndex,
          )
          .map((e) => e.selectedDoc!)
          .toSet();
      availableOptions = docOptions
          .where((op) => !selected.contains(op) || op == docField.selectedDoc)
          .toList();
    } else {
      availableOptions = docOptions;
    }

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
              items: availableOptions
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
          _compactTextField(
            property.roomTypeController,
            "Room Type (e.g. 2)",
            isNumber: true,
          ),
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
              "Documents (Required):",
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
                    currentIndex: e.key,
                    currentList: property.documents,
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
              "Images (At least 1 required):",
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
                          await Future.delayed(const Duration(seconds: 1));
                          if (context.mounted) {
                            Navigator.pop(context); // Close the mock gateway
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
