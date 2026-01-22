import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';

class TenantProfileView extends StatefulWidget {
  final String tenantUid;
  final String tenantName;
  final String landlordUid;
  final int propertyIndex;
  final int requestIndex;

  const TenantProfileView({
    super.key,
    required this.tenantUid,
    required this.tenantName,
    required this.landlordUid,
    required this.propertyIndex,
    required this.requestIndex,
  });

  @override
  State<TenantProfileView> createState() => _TenantProfileViewState();
}

class _TenantProfileViewState extends State<TenantProfileView> {
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

  // --- Hybrid Firestore Update (House Property Status) ---
  Future<void> _updateHousePropertyStatus() async {
    final String uid = widget.landlordUid;
    final int index = widget.propertyIndex;

    try {
      if (useNativeSdk) {
        // 1. Fetch current properties
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('house')
            .doc(uid)
            .get();
        if (!doc.exists) return;

        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<dynamic> properties = List.from(data['properties'] ?? []);

        // 2. Update specific index
        if (index < properties.length) {
          properties[index]['status'] = 'occupied';

          // 3. Write back
          await FirebaseFirestore.instance.collection('house').doc(uid).update({
            'properties': properties,
          });
        }
      } else {
        // REST Logic
        // 1. Fetch current properties
        final getUrl = Uri.parse(
          '$kFirestoreBaseUrl/house/$uid?key=$kFirebaseAPIKey',
        );
        final getResp = await http.get(getUrl);

        if (getResp.statusCode == 200) {
          final data = jsonDecode(getResp.body);
          List<dynamic> properties = [];

          if (data['fields'] != null && data['fields']['properties'] != null) {
            var rawList =
                data['fields']['properties']['arrayValue']['values'] as List?;
            if (rawList != null) {
              properties = rawList
                  .map((v) => _requestsParseFirestoreValue(v))
                  .toList();
            }
          }

          // 2. Update specific index locally
          if (index < properties.length) {
            properties[index]['status'] = 'occupied';

            // 3. Convert back to Firestore JSON
            List<Map<String, dynamic>> jsonValues = properties
                .map((p) => _encodeMapForFirestore(p))
                .toList();

            Map<String, dynamic> body = {
              "fields": {
                "properties": {
                  "arrayValue": {"values": jsonValues},
                },
              },
            };

            String? token = await FirebaseAuth.instance.currentUser
                ?.getIdToken();
            final patchUrl = Uri.parse(
              '$kFirestoreBaseUrl/house/$uid?updateMask.fieldPaths=properties&key=$kFirebaseAPIKey',
            );

            await http.patch(
              patchUrl,
              body: jsonEncode(body),
              headers: {
                "Content-Type": "application/json",
                if (token != null) "Authorization": "Bearer $token",
              },
            );
          }
        }
      }
    } catch (e) {
      // debugPrint("Error updating property status: $e");
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

  // Helper for REST Encoding
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

      // --- NEW: Update Property Status to 'occupied' ---
      await _updateHousePropertyStatus();

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
