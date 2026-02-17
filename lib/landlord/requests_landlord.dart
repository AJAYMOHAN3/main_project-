import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/landlord/tenant_view_from_landlord.dart';
import 'package:main_project/config.dart';

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
            return rawList.map((v) => requestsParseFirestoreValue(v)).toList();
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
            clean[k] = requestsParseFirestoreValue(v);
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
            clean[k] = requestsParseFirestoreValue(v);
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
                  builder: (_) => TenantProfileView(
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
