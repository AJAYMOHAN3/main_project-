import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:main_project/tenant/landlord_view_from_tenant.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:main_project/config.dart';

class SearchPage extends StatefulWidget {
  final VoidCallback onBack;
  const SearchPage({super.key, required this.onBack});

  @override
  SearchPageState createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  // Toggle for Map View
  bool _isMapView = false;
  final Set<Marker> _markers = {};
  final TextEditingController _searchController = TextEditingController();

  // Updated Filters: Removed People, Added Room Type
  final Map<String, TextEditingController> _filterControllers = {
    "Price": TextEditingController(),
    "Room Type": TextEditingController(),
  };

  String? _activeFilter;
  bool _showResults = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> _searchResults = [];

  // Helper for distance calculation
  final Distance _distance = const Distance();

  // Updated Filter Suggestions
  final Map<String, List<String>> filterSuggestions = {
    "Price": [
      "Below ₹5000",
      "₹5000 - ₹10000",
      "₹10000 - ₹20000",
      "Above ₹20000",
    ],
    "Room Type": ["1", "2", "3", "4", "5+"],
  };

  Future<void> _performSearch() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _showResults = true;
      _searchResults = [];
      _markers.clear();
    });

    final String searchTerm = _searchController.text.trim().toLowerCase();
    final String priceFilter = _filterControllers["Price"]!.text.trim();
    final String roomFilter = _filterControllers["Room Type"]!.text.trim();

    List<Map<String, dynamic>> allProperties = [];

    try {
      // 1. FETCH ALL PROPERTIES
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        QuerySnapshot houseSnapshot = await FirebaseFirestore.instance
            .collection('house')
            .get();

        for (var doc in houseSnapshot.docs) {
          String landlordUid = doc.id;
          var houseData = doc.data() as Map<String, dynamic>?;

          if (houseData != null &&
              houseData.containsKey('properties') &&
              houseData['properties'] is List) {
            List<dynamic> props = houseData['properties'];
            for (int i = 0; i < props.length; i++) {
              if (props[i] is Map<String, dynamic>) {
                allProperties.add({
                  'landlordUid': landlordUid,
                  'propertyIndex': i,
                  'propertyDetails': props[i],
                });
              }
            }
          }
        }
      } else {
        // REST Implementation
        final url = Uri.parse('$kFirestoreBaseUrl/house?key=$kFirebaseAPIKey');
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['documents'] != null) {
            for (var doc in data['documents']) {
              String landlordUid = doc['name'].split('/').last;
              if (doc['fields'] != null &&
                  doc['fields']['properties'] != null &&
                  doc['fields']['properties']['arrayValue'] != null) {
                var values =
                    doc['fields']['properties']['arrayValue']['values']
                        as List?;
                if (values != null) {
                  List<dynamic> props = values.map((v) {
                    if (v['mapValue'] != null &&
                        v['mapValue']['fields'] != null) {
                      Map<String, dynamic> cleanMap = {};
                      v['mapValue']['fields'].forEach((key, val) {
                        // FIX: Better parsing for arrays specifically
                        if (val.containsKey('arrayValue')) {
                          var arrayVals = val['arrayValue']['values'] as List?;
                          if (arrayVals != null) {
                            // Extract the actual string/int values from the array
                            cleanMap[key] = arrayVals.map((item) {
                              if (item.containsKey('stringValue')) {
                                return item['stringValue'];
                              }
                              if (item.containsKey('integerValue')) {
                                return int.tryParse(
                                  item['integerValue'] ?? '0',
                                );
                              }
                              return null;
                            }).toList();
                          } else {
                            cleanMap[key] = [];
                          }
                        } else {
                          cleanMap[key] = parseFirestoreRestValue(val);
                        }
                      });
                      return cleanMap;
                    }
                    return {};
                  }).toList();

                  for (int i = 0; i < props.length; i++) {
                    allProperties.add({
                      'landlordUid': landlordUid,
                      'propertyIndex': i,
                      'propertyDetails': props[i],
                    });
                  }
                }
              }
            }
          }
        }
      }

      // 2. LOGIC: DETERMINE TARGET COORDINATES
      // Check if we can find coordinates for the search term either from
      // existing houses OR from the internet.
      List<LatLng> targetLocations = [];

      if (searchTerm.isNotEmpty) {
        // A. Internal Check: Does a house in DB have this location/panchayat name?
        // If yes, use its coordinates as a reference point.
        for (var item in allProperties) {
          var p = item['propertyDetails'];
          String loc = (p['location'] as String? ?? '').toLowerCase();
          String panchayat = (p['panchayatName'] as String? ?? '')
              .toLowerCase();

          if (loc.contains(searchTerm) || panchayat.contains(searchTerm)) {
            double? lat = double.tryParse(p['latitude'].toString());
            double? lng = double.tryParse(p['longitude'].toString());
            if (lat != null && lng != null) {
              targetLocations.add(LatLng(lat, lng));
            }
          }
        }

        // B. External Check: If DB had no matches, ask OpenStreetMap
        if (targetLocations.isEmpty) {
          try {
            final geoUrl = Uri.parse(
              'https://nominatim.openstreetmap.org/search?q=$searchTerm&format=json&limit=1',
            );
            final geoResponse = await http.get(
              geoUrl,
              headers: {'User-Agent': 'com.securehomes.rental_project'},
            );

            if (geoResponse.statusCode == 200) {
              final geoData = jsonDecode(geoResponse.body) as List;
              if (geoData.isNotEmpty) {
                double lat = double.parse(geoData[0]['lat']);
                double lon = double.parse(geoData[0]['lon']);
                targetLocations.add(LatLng(lat, lon));
              }
            }
          } catch (_) {
            // Ignore external errors
          }
        }
      }

      // 3. FILTER PROPERTIES (Radius OR Name + Room Type + Price)
      List<Map<String, dynamic>> finalResults = [];

      for (var item in allProperties) {
        var p = item['propertyDetails'];

        // Status Check
        String status = (p['status'] as String? ?? 'active').toLowerCase();
        if (status == 'occupied' || status == 'deleted') continue;

        // --- LOCATION FILTER LOGIC ---
        bool locationMatch = false;

        if (searchTerm.isEmpty) {
          locationMatch = true;
        } else {
          // Check 1: Is it physically within 15km of target coordinates?
          bool isRadiusMatch = false;
          if (targetLocations.isNotEmpty) {
            double? lat = double.tryParse(p['latitude'].toString());
            double? lng = double.tryParse(p['longitude'].toString());

            if (lat != null && lng != null) {
              LatLng currentPos = LatLng(lat, lng);
              for (var target in targetLocations) {
                if (_distance.as(LengthUnit.Kilometer, currentPos, target) <=
                    15) {
                  isRadiusMatch = true;
                  break;
                }
              }
            }
          }

          // Check 2: Does the name match explicitly?
          bool isStringMatch = false;
          String loc = (p['location'] as String? ?? '').toLowerCase();
          String panchayat = (p['panchayatName'] as String? ?? '')
              .toLowerCase();
          if (loc.contains(searchTerm) || panchayat.contains(searchTerm)) {
            isStringMatch = true;
          }

          // Final Logic: It matches if it's in the Radius OR matches the Name
          if (isRadiusMatch || isStringMatch) {
            locationMatch = true;
          }
        }

        if (!locationMatch) continue;

        // --- SUB-FILTERS (Room Type & Price) ---

        // Room Type Match
        String dbRoomType = p['roomType'].toString().trim().toLowerCase();
        dbRoomType = dbRoomType.replaceAll(RegExp(r'[^0-9]'), '');

        bool roomMatch = true;
        if (roomFilter.isNotEmpty) {
          String filterNum = roomFilter.replaceAll(RegExp(r'[^0-9]'), '');
          if (filterNum == "5") {
            int? type = int.tryParse(dbRoomType);
            roomMatch = (type != null && type >= 5);
          } else {
            roomMatch = dbRoomType == filterNum;
          }
        }

        // Price Match
        String rentStr = p['rent'] as String? ?? '';
        bool priceMatch =
            priceFilter.isEmpty || _checkPriceMatch(rentStr, priceFilter);

        if (locationMatch && roomMatch && priceMatch) {
          finalResults.add(item);
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = finalResults;
          _isLoading = false;

          // BUILD MAP MARKERS FOR RESULTS
          _markers.clear();
          for (var result in _searchResults) {
            var property = result['propertyDetails'];
            double? lat = double.tryParse(property['latitude'].toString());
            double? lng = double.tryParse(property['longitude'].toString());

            String? imageUrl;
            // FIX: Safely check for non-empty string in the array
            if (property['houseImageUrls'] != null &&
                property['houseImageUrls'] is List) {
              for (var url in property['houseImageUrls']) {
                if (url != null && url.toString().trim().isNotEmpty) {
                  imageUrl = url.toString().trim();
                  break;
                }
              }
            }

            if (lat != null && lng != null) {
              _markers.add(
                Marker(
                  point: LatLng(lat, lng),
                  width: 50,
                  height: 50,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LandlordsearchProfilePage(
                            landlordUid: result['landlordUid'],
                            propertyDetails: result['propertyDetails'],
                            propertyIndex: result['propertyIndex'],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.orange, width: 2),
                        color: Colors.white,
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                      child: ClipOval(
                        child: imageUrl != null
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                    const Icon(Icons.home, color: Colors.grey),
                              )
                            : const Icon(Icons.home, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              );
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _checkPriceMatch(String rentStr, String priceFilter) {
    int? rent = int.tryParse(rentStr.replaceAll(RegExp(r'[^0-9]'), '').trim());
    if (rent == null) return false;

    switch (priceFilter) {
      case "Below ₹5000":
        return rent < 5000;
      case "₹5000 - ₹10000":
        return rent >= 5000 && rent <= 10000;
      case "₹10000 - ₹20000":
        return rent > 10000 && rent <= 20000;
      case "Above ₹20000":
        return rent > 20000;
      default:
        return true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevent map resize on keyboard
      body: Stack(
        children: [
          const AnimatedGradientBackground(),

          // --- MAIN CONTENT ---
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: 'Search',
                  onBack: widget.onBack,
                ),

                // SEARCH & FILTER HEADER
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: "Search location...",
                                hintStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.08),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(
                                    Icons.search,
                                    color: Colors.orange,
                                  ),
                                  onPressed: _performSearch,
                                ),
                              ),
                              onSubmitted: (_) => _performSearch(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // TOGGLE MAP VIEW BUTTON
                          Container(
                            decoration: BoxDecoration(
                              color: _isMapView
                                  ? Colors.orange
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: Icon(
                                _isMapView ? Icons.list : Icons.map,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isMapView = !_isMapView;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // FILTERS ROW
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ["Price", "Room Type"].map((filter) {
                            bool isActive = _activeFilter == filter;
                            String currentVal =
                                _filterControllers[filter]!.text;
                            bool hasValue = currentVal.isNotEmpty;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _activeFilter = isActive ? null : filter;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: (isActive || hasValue)
                                      ? Colors.orange.shade300
                                      : Colors.white.withValues(alpha: 0.15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  hasValue ? "$filter: $currentVal" : filter,
                                  style: TextStyle(
                                    color: (isActive || hasValue)
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      // FILTER OPTIONS DROPDOWN
                      if (_activeFilter != null)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: filterSuggestions[_activeFilter!]!
                                .map(
                                  (option) => ChoiceChip(
                                    label: Text(option),
                                    selected:
                                        _filterControllers[_activeFilter!]!
                                            .text ==
                                        option,
                                    selectedColor: Colors.orange,
                                    onSelected: (selected) {
                                      setState(() {
                                        _filterControllers[_activeFilter!]!
                                            .text = selected
                                            ? option
                                            : '';
                                        _activeFilter = null;
                                      });
                                      _performSearch(); // Auto-search on filter change
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),

                // RESULTS AREA
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.orange,
                          ),
                        )
                      : _isMapView
                      // --- MAP VIEW ---
                      ? FlutterMap(
                          options: const MapOptions(
                            initialCenter: LatLng(
                              9.9312,
                              76.2673,
                            ), // Default Kochi
                            initialZoom: 10.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'com.securehomes.rental_project',
                            ),
                            MarkerLayer(markers: _markers.toList()),
                          ],
                        )
                      // --- LIST VIEW ---
                      : (_searchResults.isEmpty && _showResults)
                      ? const Center(
                          child: Text(
                            "No homes found nearby.",
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            final property = result['propertyDetails'];

                            String? imageUrl;
                            if (property['houseImageUrls'] != null &&
                                (property['houseImageUrls'] as List)
                                    .isNotEmpty) {
                              imageUrl = property['houseImageUrls'][0];
                            }

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        LandlordsearchProfilePage(
                                          landlordUid: result['landlordUid'],
                                          propertyDetails:
                                              result['propertyDetails'],
                                          propertyIndex:
                                              result['propertyIndex'],
                                        ),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Row(
                                  children: [
                                    // Image
                                    ClipRRect(
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                            left: Radius.circular(15),
                                          ),
                                      child: SizedBox(
                                        width: 110,
                                        height: 110,
                                        child: imageUrl != null
                                            ? Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: Colors.grey,
                                                child: const Icon(Icons.home),
                                              ),
                                      ),
                                    ),
                                    // Details
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "${property['roomType']} BHK", // Updated to just show Number + BHK
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.location_on,
                                                  color: Colors.white70,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    property['location'] ?? '',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              "₹${property['rent']}/mo",
                                              style: const TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.white30,
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
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
