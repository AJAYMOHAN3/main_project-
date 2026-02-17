import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:main_project/config.dart';

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

  // --- UPDATED: Function to Fetch Property Documents ---
  Future<void> _fetchPropertyDocuments() async {
    // FIX: Use the actual 'folderName' from DB instead of calculating index
    String propertyFolderName =
        widget.propertyDetails['folderName'] ??
        'property${widget.propertyIndex + 1}';

    String docPath = '${widget.landlordUid}/$propertyFolderName/';

    // 1. SDK LOGIC (Android/iOS)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final storageRef = FirebaseStorage.instance.ref().child(docPath);
        final listResult = await storageRef.listAll();

        // items contains files, prefixes contains folders (like 'images')
        // We only want files in the root of property folder
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
      // FIX: Load images directly from DB URL list first
      if (widget.propertyDetails['houseImageUrls'] != null) {
        List<dynamic> dbImages = widget.propertyDetails['houseImageUrls'];
        if (dbImages.isNotEmpty) {
          setState(() {
            _propertyImageUrls = List<String>.from(dbImages);
          });
        }
      }

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

        // 3. Fallback: Fetch Property Images from Storage if DB list was empty
        if (_propertyImageUrls.isEmpty) {
          List<String> imageUrls = [];
          // FIX: Use folderName from DB
          String propertyFolderName =
              widget.propertyDetails['folderName'] ??
              'property${widget.propertyIndex + 1}';
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

        // 3. Fallback: Fetch Property Images from Storage if DB list was empty
        if (_propertyImageUrls.isEmpty) {
          // FIX: Use folderName from DB
          String propertyFolderName =
              widget.propertyDetails['folderName'] ??
              'property${widget.propertyIndex + 1}';
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
                        cleanMap[key] = parseFirestoreRestValues(val);
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

dynamic parseFirestoreRestValues(Map<String, dynamic> valueMap) {
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
    return values.map((v) => parseFirestoreRestValues(v)).toList();
  }
  return null;
}
