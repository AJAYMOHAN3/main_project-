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

class SearchPage extends StatefulWidget {
  final VoidCallback onBack;
  const SearchPage({super.key, required this.onBack});

  @override
  SearchPageState createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  final Set<Marker> _markers = {};
  final TextEditingController _searchController = TextEditingController();
  final Map<String, TextEditingController> _filterControllers = {
    "Price": TextEditingController(),
    "People": TextEditingController(),
  };

  String? _activeFilter;
  bool _showResults = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> _searchResults = [];

  final Map<String, List<String>> filterSuggestions = {
    "Price": [
      "Below ₹5000",
      "₹5000 - ₹10000",
      "₹10000 - ₹20000",
      "Above ₹20000",
    ],
    "People": ["1 person", "2 people", "3 people", "4+ people"],
  };

  Future<void> _performSearch() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _showResults = true;
      _searchResults = [];
    });

    final bool isFilterActive =
        _filterControllers["Price"]!.text.isNotEmpty ||
        _filterControllers["People"]!.text.isNotEmpty;

    final String searchTerm = isFilterActive
        ? ""
        : _searchController.text.trim().toLowerCase();

    final String priceFilter = _filterControllers["Price"]!.text.trim();
    final String peopleFilter = _filterControllers["People"]!.text.trim();

    List<Map<String, dynamic>> results = [];

    try {
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
            List<dynamic> properties = houseData['properties'];
            _filterAndAddProperties(
              properties,
              landlordUid,
              searchTerm,
              priceFilter,
              peopleFilter,
              results,
            );
          }
        }
      } else {
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
                  List<dynamic> properties = values.map((v) {
                    if (v['mapValue'] != null &&
                        v['mapValue']['fields'] != null) {
                      Map<String, dynamic> cleanMap = {};
                      v['mapValue']['fields'].forEach((key, val) {
                        cleanMap[key] = _parseFirestoreRestValue(val);
                      });
                      return cleanMap;
                    }
                    return {};
                  }).toList();

                  _filterAndAddProperties(
                    properties,
                    landlordUid,
                    searchTerm,
                    priceFilter,
                    peopleFilter,
                    results,
                  );
                }
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;

          _markers.clear();
          for (var result in _searchResults) {
            var property = result['propertyDetails'];
            double lat =
                double.tryParse(property['latitude'].toString()) ?? 10.0;
            double lng =
                double.tryParse(property['longitude'].toString()) ?? 76.0;

            _markers.add(
              Marker(
                point: LatLng(lat, lng),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () {},
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.orange,
                    size: 36,
                  ),
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching houses: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterAndAddProperties(
    List<dynamic> properties,
    String landlordUid,
    String searchTerm,
    String priceFilter,
    String peopleFilter,
    List<Map<String, dynamic>> results,
  ) {
    for (int i = 0; i < properties.length; i++) {
      var property = properties[i];
      if (property is Map<String, dynamic>) {
        String status = (property['status'] as String? ?? 'active')
            .toLowerCase();
        if (status == 'occupied' || status == 'deleted') {
          continue;
        }

        String location = (property['location'] as String? ?? '').toLowerCase();
        String rentStr = property['rent'] as String? ?? '';
        String occupancyStr = property['maxOccupancy'] as String? ?? '';
        String roomType = property['roomType'] as String? ?? '';

        bool priceMatch =
            priceFilter.isEmpty || _checkPriceMatch(rentStr, priceFilter);
        bool peopleMatch =
            peopleFilter.isEmpty ||
            _checkOccupancyMatch(occupancyStr, peopleFilter);

        bool searchMatch =
            searchTerm.isEmpty ||
            location.contains(searchTerm) ||
            roomType.toLowerCase().contains(searchTerm) ||
            rentStr.contains(searchTerm) ||
            occupancyStr.toLowerCase().contains(searchTerm);

        if (priceMatch && peopleMatch && searchMatch) {
          results.add({
            'landlordUid': landlordUid,
            'propertyIndex': i,
            'displayInfo':
                '${roomType.isNotEmpty ? roomType : "Property"} - ${property['location'] ?? 'Unknown Location'}',
            'propertyDetails': property,
          });
        }
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

  bool _checkOccupancyMatch(String occupancyStr, String peopleFilter) {
    int? occupancy = int.tryParse(
      occupancyStr.replaceAll(RegExp(r'[^0-9]'), '').trim(),
    );
    if (occupancy == null) return false;

    switch (peopleFilter) {
      case "1 person":
        return occupancy >= 1;
      case "2 people":
        return occupancy >= 2;
      case "3 people":
        return occupancy >= 3;
      case "4+ people":
        return occupancy >= 4;
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
    final bool isFilterActive =
        _filterControllers["Price"]!.text.isNotEmpty ||
        _filterControllers["People"]!.text.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                // --- MOVED NAVBAR HERE (Outside Padding) ---
                CustomTopNavBar(
                  showBack: true,
                  title: 'Search',
                  onBack: widget.onBack,
                ),

                // --- Scrollable Content starts AFTER Navbar ---
                SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Center(
                          child: Text(
                            "SEARCH HOMES",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                            ),
                            softWrap: true,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: ["Price", "People"].map((filter) {
                              bool isActive = _activeFilter == filter;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ElevatedButton.icon(
                                  icon: Icon(
                                    Icons.filter_alt,
                                    color: isActive
                                        ? Colors.black
                                        : Colors.white,
                                    size: 18,
                                  ),
                                  label: Text(
                                    filter,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isActive
                                        ? Colors.orange.shade300
                                        : Colors.white.withValues(alpha: 0.15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _activeFilter = isActive ? null : filter;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        if (_activeFilter != null)
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller:
                                      _filterControllers[_activeFilter!],
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText:
                                        "Enter ${_activeFilter!.toLowerCase()}...",
                                    hintStyle: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: 0.08,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onSubmitted: (_) => _performSearch(),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: filterSuggestions[_activeFilter!]!
                                      .map(
                                        (option) => ChoiceChip(
                                          label: Text(option),
                                          labelStyle: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.1),
                                          selectedColor: Colors.orange.shade700,
                                          selected:
                                              _filterControllers[_activeFilter!]!
                                                  .text ==
                                              option,
                                          onSelected: (selected) {
                                            setState(() {
                                              _filterControllers[_activeFilter!]!
                                                  .text = selected
                                                  ? option
                                                  : '';
                                              _activeFilter = null;
                                            });
                                            _performSearch();
                                          },
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        if (!isFilterActive)
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: "Search homes...",
                                    hintStyle: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: 0.08,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => _performSearch(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _performSearch,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade700,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.search,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                if (_showResults)
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.orange,
                            ),
                          )
                        : (_searchResults.isEmpty
                              ? const Center(
                                  child: Text(
                                    "No homes found.",
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  itemCount: _searchResults.length,
                                  itemBuilder: (context, index) {
                                    final result = _searchResults[index];
                                    final property = result['propertyDetails'];

                                    String? imageUrl;
                                    if (property['houseImageUrls'] != null &&
                                        property['houseImageUrls'] is List &&
                                        (property['houseImageUrls'] as List)
                                            .isNotEmpty) {
                                      imageUrl = property['houseImageUrls'][0];
                                    }

                                    final String location =
                                        property['location'] ?? 'Unknown';
                                    final String rent =
                                        property['rent'] ?? 'N/A';
                                    final String roomType =
                                        property['roomType'] ?? 'Room';

                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                LandlordsearchProfilePage(
                                                  landlordUid:
                                                      result['landlordUid'],
                                                  propertyDetails:
                                                      result['propertyDetails'],
                                                  propertyIndex:
                                                      result['propertyIndex'],
                                                ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        height: 120,
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.only(
                                                    topLeft: Radius.circular(
                                                      15,
                                                    ),
                                                    bottomLeft: Radius.circular(
                                                      15,
                                                    ),
                                                  ),
                                              child: SizedBox(
                                                width: 120,
                                                height: double.infinity,
                                                child: imageUrl != null
                                                    ? Image.network(
                                                        imageUrl,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              ctx,
                                                              err,
                                                              stack,
                                                            ) => Container(
                                                              color: Colors
                                                                  .grey[800],
                                                              child: const Icon(
                                                                Icons
                                                                    .broken_image,
                                                                color: Colors
                                                                    .white54,
                                                              ),
                                                            ),
                                                      )
                                                    : Container(
                                                        color: Colors.grey[800],
                                                        child: const Icon(
                                                          Icons.home,
                                                          color: Colors.white54,
                                                          size: 40,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                            // FIX: Wrap the text column in Expanded to take remaining space
                                            // and force text clipping to prevent right overflow
                                            Expanded(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12.0,
                                                      vertical: 8.0,
                                                    ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      roomType,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.location_on,
                                                          size: 14,
                                                          color: Colors.white70,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        // Flexible allows text to shrink if needed
                                                        Flexible(
                                                          child: Text(
                                                            location,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white70,
                                                                  fontSize: 14,
                                                                ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      "₹$rent/mo",
                                                      style: const TextStyle(
                                                        color:
                                                            Colors.orangeAccent,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width:
                                                  28, // hard constraint prevents overflow
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 12.0,
                                                ),
                                                child: const Icon(
                                                  Icons.arrow_forward_ios,
                                                  color: Colors.white30,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                )),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  if (valueMap.containsKey('mapValue')) {
    var fields = valueMap['mapValue']['fields'] as Map<String, dynamic>?;
    if (fields == null) return {};
    var result = <String, dynamic>{};
    fields.forEach((key, value) {
      result[key] = _parseFirestoreRestValue(value);
    });
    return result;
  }
  return null;
}
