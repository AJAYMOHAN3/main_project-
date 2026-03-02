import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:main_project/config.dart';

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
                requestsParseFirestoreValue(data['fields']['requests'])
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

  // --- Hybrid Data Fetch for Requests ---
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
            res[k] = requestsParseFirestoreValue(v);
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
            content: Text("Request Accepted! Awaiting Tenant Payment."),
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
