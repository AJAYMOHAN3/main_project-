import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';

class RequestsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const RequestsPage2({super.key, required this.onBack});

  @override
  State<RequestsPage2> createState() => _RequestsPageState2();
}

class _RequestsPageState2 extends State<RequestsPage2> {
  final String currentUserId = uid;

  // Helper to determine platform
  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // --- REST API: Fetch Requests ---
  Future<List<dynamic>> _fetchRequestsRest() async {
    if (currentUserId.isEmpty) return [];
    try {
      final url = Uri.parse(
        '$kFirestoreBaseUrl/trequests/$currentUserId?key=$kFirebaseAPIKey',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Parse the Firestore JSON structure
        if (data['fields'] != null && data['fields']['requests'] != null) {
          // 'requests' is an arrayValue
          var rawList =
              data['fields']['requests']['arrayValue']['values'] as List?;
          if (rawList != null) {
            // Convert using the helper
            return rawList.map((v) => _parseFirestoreRestValues(v)).toList();
          }
        }
      }
      return [];
    } catch (e) {
      // print("REST Fetch Error: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedGradientBackground(), // Assuming this widget exists globally
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
                      "My Requests",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: currentUserId.isEmpty
                      ? const Center(
                          child: Text("Please login to view requests"),
                        )
                      : useNativeSdk
                      // --- MOBILE: USE SDK (STREAM) ---
                      ? StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('trequests')
                              .doc(currentUserId)
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
                      // --- WEB/DESKTOP: USE HTTP (FUTURE) ---
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
        "No requests sent yet.",
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildRequestsList(List<dynamic> requests) {
    if (requests.isEmpty) return _buildEmptyState();

    return ListView.builder(
      itemCount: requests.length,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemBuilder: (context, index) {
        final reqData = requests[index] as Map<String, dynamic>;

        final String landlordUid = reqData['luid'] ?? '';
        final String status = reqData['status'] ?? 'pending';

        int propertyIndex = 0;
        if (reqData['propertyIndex'] is int) {
          propertyIndex = reqData['propertyIndex'];
        } else if (reqData['propertyIndex'] is String) {
          propertyIndex = int.tryParse(reqData['propertyIndex']) ?? 0;
        }

        return _RequestCard(
          landlordUid: landlordUid,
          propertyIndex: propertyIndex,
          status: status,
          useNativeSdk: useNativeSdk, // Pass platform flag
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helper Widget: Fetches Property Data
// ---------------------------------------------------------------------------
class _RequestCard extends StatelessWidget {
  final String landlordUid;
  final int propertyIndex;
  final String status;
  final bool useNativeSdk;

  const _RequestCard({
    required this.landlordUid,
    required this.propertyIndex,
    required this.status,
    required this.useNativeSdk,
  });

  // --- Logic to Fetch House Data (Hybrid: SDK or REST) ---
  Future<Map<String, dynamic>?> _fetchHouseData() async {
    if (useNativeSdk) {
      // SDK Logic
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('house')
            .doc(landlordUid)
            .get();
        if (doc.exists) {
          return doc.data() as Map<String, dynamic>;
        }
      } catch (e) {
        return null;
      }
    } else {
      // REST Logic
      try {
        final url = Uri.parse(
          '$kFirestoreBaseUrl/house/$landlordUid?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null) {
            // Convert the entire document fields to a clean Map
            Map<String, dynamic> cleanData = {};
            data['fields'].forEach((key, val) {
              cleanData[key] = _parseFirestoreRestValues(val);
            });
            return cleanData;
          }
        }
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String displayStatus = status.toUpperCase();

    switch (status.toLowerCase()) {
      case 'accepted':
      case 'approved':
        statusColor = Colors.lightGreenAccent;
        break;
      case 'rejected':
      case 'declined':
        statusColor = Colors.redAccent;
        break;
      default:
        statusColor = Colors.amberAccent;
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchHouseData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            color: Colors.white.withValues(alpha: 0.1),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const SizedBox(
              height: 100,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox(); // Hide if house not found
        }

        final houseData = snapshot.data!;
        final List<dynamic> properties = houseData['properties'] ?? [];

        if (propertyIndex >= properties.length) {
          return const SizedBox();
        }

        final property = properties[propertyIndex];
        // Note: For REST, 'property' is already parsed into a Map by _parseFirestoreRestValue

        final String location = property['location'] ?? 'Unknown Location';
        final String rent = property['rent'].toString();
        final String roomType = property['apartmentName'] ?? "My Apartment";

        String imageUrl = '';
        if (property['houseImageUrls'] != null &&
            (property['houseImageUrls'] as List).isNotEmpty) {
          imageUrl = property['houseImageUrls'][0];
        }

        return Card(
          color: Colors.white.withValues(alpha: 0.1),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: Container(
                  width: 100,
                  height: 100,
                  color: Colors.black26,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.broken_image,
                                color: Colors.white54,
                              ),
                        )
                      : const Icon(Icons.home, color: Colors.white54),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roomType,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Rent: ₹$rent",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.2),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Status: $displayStatus",
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helper Function: Parse Firestore REST JSON
// ---------------------------------------------------------------------------
dynamic _parseFirestoreRestValues(Map<String, dynamic> valueMap) {
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
    return values.map((v) => _parseFirestoreRestValues(v)).toList();
  }

  if (valueMap.containsKey('mapValue')) {
    var fields = valueMap['mapValue']['fields'] as Map<String, dynamic>?;
    if (fields == null) return {};
    Map<String, dynamic> result = {};
    fields.forEach((key, val) {
      result[key] = _parseFirestoreRestValues(val);
    });
    return result;
  }
  return null;
}
