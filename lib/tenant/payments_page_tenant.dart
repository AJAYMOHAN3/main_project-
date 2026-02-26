import 'dart:convert';
import 'dart:io'; // Required for Platform check
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for input formatters
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:main_project/config.dart';
import 'package:pdf/pdf.dart'; // FIX: Required for PdfColors
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';

// DAG IMPORT - Adjust path if your dag_engine.dart is in a different directory
import 'package:main_project/dag/dag_engine.dart';

class PaymentsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage2({super.key, required this.onBack});

  @override
  State<PaymentsPage2> createState() => _PaymentsPage2State();
}

class _PaymentsPage2State extends State<PaymentsPage2> {
  bool _isProcessing = false;

  // Payment State Management
  String _paymentMode = 'loading'; // 'loading', 'none', 'agreement', 'rent'
  double _rentAmount = 0;
  double _secAmount = 0;
  double _dueAmount = 0;
  String _landlordUid = "";
  int _propertyIndex = 0;
  Map<String, dynamic>? _pendingProp;

  bool get _isNativeMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    if (_isNativeMobile) {
      Stripe.publishableKey = stripePublishableKey;
    }
    _checkPaymentStatus();
  }

  // --- COMPREHENSIVE PAYMENT STATUS CHECKER ---
  Future<void> _checkPaymentStatus() async {
    try {
      // 1. Check for Pending Initial Agreement Payment
      final tReqMap = await _fetchDocData('trequests', uid);
      List<dynamic> reqs = tReqMap['requests'] ?? [];

      bool hasPendingAgreement = false;
      for (int i = 0; i < reqs.length; i++) {
        var r = reqs[i];
        if (r['status'] == 'accepted') {
          _landlordUid = r['luid'];
          _propertyIndex = r['propertyIndex'];

          final hMap = await _fetchDocData('house', _landlordUid);
          List<dynamic> props = hMap['properties'] ?? [];

          if (_propertyIndex < props.length) {
            _pendingProp = props[_propertyIndex];
            _rentAmount =
                double.tryParse(_pendingProp!['rent'].toString()) ?? 0;
            _secAmount =
                double.tryParse(_pendingProp!['securityAmount'].toString()) ??
                0;
            _dueAmount = _rentAmount + _secAmount;

            if (mounted) {
              setState(() {
                _paymentMode = 'agreement';
              });
            }
          }
          hasPendingAgreement = true;
          break;
        }
      }

      if (hasPendingAgreement) return;

      // 2. Check for Due Monthly Rent (30 days logic)
      final tAgrMap = await _fetchDocData('tagreements', uid);
      List<dynamic> agreements = tAgrMap['agreements'] ?? [];

      if (agreements.isNotEmpty) {
        // Use the latest agreement
        var activeAgr = agreements.last;
        _landlordUid = activeAgr['landlordUid'];
        _rentAmount = double.tryParse(activeAgr['rentAmount'].toString()) ?? 0;
        _dueAmount = _rentAmount;
        _secAmount = 0;

        // Find last payment date to this landlord
        final paymentsMap = await _fetchDocData('payments', uid);
        List<dynamic> payments = paymentsMap['payments'] ?? [];

        DateTime? lastPaymentDate;
        for (var p in payments.reversed) {
          if (p['landlordUid'] == _landlordUid) {
            lastPaymentDate = DateTime.tryParse(p['timestamp'].toString());
            break;
          }
        }

        // If no payment found (unlikely if agreement exists), or if > 30 days
        if (lastPaymentDate == null ||
            DateTime.now().difference(lastPaymentDate).inDays >= 30) {
          if (mounted) {
            setState(() {
              _paymentMode = 'rent';
            });
          }
          return;
        }
      }

      // 3. No Payments Due
      if (mounted) {
        setState(() {
          _paymentMode = 'none';
        });
      }
    } catch (e) {
      debugPrint("Error fetching payment status: $e");
      if (mounted) setState(() => _paymentMode = 'none');
    }
  }

  // --- PAYMENT LOGIC ---
  void _handlePaymentClick() {
    if (_dueAmount <= 0) return;
    String amountStr = _dueAmount.toInt().toString();

    if (_paymentMode == 'agreement') {
      final date = DateTime.now();
      final dateStr = "${date.day}/${date.month}/${date.year}";
      // Calculate End Date (11 months)
      DateTime endDateObj = DateTime(date.year, date.month + 11, date.day);
      final endDateStr =
          "${endDateObj.day}/${endDateObj.month}/${endDateObj.year}";

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            "TERMS AND CONDITIONS",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Rent Amount: The monthly rent is fixed at Rs. ${_rentAmount.toInt()}.",
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 8),
              Text(
                "Security Deposit: The Lessee has paid a sum of Rs. ${_secAmount.toInt()}.",
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 8),
              Text(
                "Period of Tenancy: The tenancy is for a period of 11 months from $dateStr to $endDateStr.",
                style: const TextStyle(color: Colors.black),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                Navigator.pop(ctx);
                _processActualPayment(amountStr);
              },
              child: const Text(
                "Accept & Pay",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } else if (_paymentMode == 'rent') {
      _processActualPayment(amountStr);
    }
  }

  Future<void> _processActualPayment(String amountStr) async {
    setState(() => _isProcessing = true);

    if (_isNativeMobile) {
      try {
        final paymentIntentData = await _createPaymentIntent(amountStr, 'INR');
        final String paymentId = paymentIntentData['id'];

        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: paymentIntentData['client_secret'],
            merchantDisplayName: 'Secure Homes',
            style: ThemeMode.dark,
          ),
        );

        await _displayPaymentSheet(amountStr, paymentId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    } else {
      setState(() => _isProcessing = false);
      _showMockPaymentSystem(amountStr);
    }
  }

  Future<void> _displayPaymentSheet(String amount, String paymentId) async {
    try {
      await Stripe.instance.presentPaymentSheet().then((value) async {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Payment of ₹$amount Successful!"),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _savePaymentToFirestore(amount, paymentId);

        if (_paymentMode == 'agreement') {
          await _generateAgreement();
        }

        // Refresh Status
        await _checkPaymentStatus();
      });
    } on StripeException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Payment Cancelled"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _createPaymentIntent(
    String amount,
    String currency,
  ) async {
    try {
      int amountInSmallestUnit = (double.parse(amount) * 100).toInt();
      Map<String, dynamic> body = {
        'amount': amountInSmallestUnit.toString(),
        'currency': currency,
        'payment_method_types[]': 'card',
      };
      var response = await http.post(
        Uri.parse('https://api.stripe.com/v1/payment_intents'),
        headers: {
          'Authorization': 'Bearer $stripeSecretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );
      return jsonDecode(response.body);
    } catch (err) {
      throw Exception(err.toString());
    }
  }

  // --- SAVING DATA (HYBRID) ---
  Future<void> _savePaymentToFirestore(String amount, String paymentId) async {
    String tenantName = "Unknown";
    String timestamp = DateTime.now().toString();
    String method = _isNativeMobile ? 'Stripe Card' : 'Card (Web/Desktop)';
    String type = _paymentMode == 'agreement'
        ? 'Agreement Payment'
        : 'Monthly Rent';

    try {
      if (_isNativeMobile) {
        DocumentSnapshot tenantDoc = await FirebaseFirestore.instance
            .collection('tenant')
            .doc(uid)
            .get();
        if (tenantDoc.exists && tenantDoc.data() != null) {
          var data = tenantDoc.data() as Map<String, dynamic>;
          if (data.containsKey('fullName')) tenantName = data['fullName'];
        }

        final paymentData = {
          'transId': paymentId,
          'amount': amount,
          'tenantName': tenantName,
          'timestamp': timestamp,
          'method': method,
          'status': 'Success',
          'type': type,
          'landlordUid': _landlordUid,
        };

        await FirebaseFirestore.instance.collection('payments').doc(uid).set({
          'payments': FieldValue.arrayUnion([paymentData]),
        }, SetOptions(merge: true));
      } else {
        final nameUrl = Uri.parse(
          '$kFirestoreBaseUrl/tenant/$uid?key=$kFirebaseAPIKey',
        );
        final nameResp = await http.get(nameUrl);
        if (nameResp.statusCode == 200) {
          final data = jsonDecode(nameResp.body);
          if (data['fields'] != null && data['fields']['fullName'] != null) {
            tenantName = data['fields']['fullName']['stringValue'] ?? "Unknown";
          }
        }

        final commitUrl = Uri.parse(
          '$kFirestoreBaseUrl:commit?key=$kFirebaseAPIKey',
        );
        final body = jsonEncode({
          "writes": [
            {
              "transform": {
                "document":
                    "projects/$kProjectId/databases/(default)/documents/payments/$uid",
                "fieldTransforms": [
                  {
                    "fieldPath": "payments",
                    "appendMissingElements": {
                      "values": [
                        {
                          "mapValue": {
                            "fields": {
                              "transId": {"stringValue": paymentId},
                              "amount": {"stringValue": amount},
                              "tenantName": {"stringValue": tenantName},
                              "timestamp": {"stringValue": timestamp},
                              "method": {"stringValue": method},
                              "status": {"stringValue": "Success"},
                              "type": {"stringValue": type},
                              "landlordUid": {"stringValue": _landlordUid},
                            },
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            },
          ],
        });

        await http.post(
          commitUrl,
          body: body,
          headers: {'Content-Type': 'application/json'},
        );
      }

      // --- DAG INTEGRATION: STORE PAYMENT STAMP ---
      final String paymentJson = jsonEncode({
        "type": type,
        "amount": amount,
        "tenantUid": uid,
        "landlordUid": _landlordUid,
        "transId": paymentId,
        "timestamp": timestamp,
      });
      // Mine and append the payment record to the DAG network
      await DagLedger.instance.addTransaction(paymentJson);
    } catch (e) {
      debugPrint("Error saving payment: $e");
    }
  }

  // --- AUTOMATED AGREEMENT GENERATION ---
  Future<void> _generateAgreement() async {
    try {
      final tData = await _fetchDocData('tenant', uid);
      final lData = await _fetchDocData('landlord', _landlordUid);

      final String tName = tData['fullName'] ?? "Tenant";
      final String tAadhaar = tData['aadharNumber'] ?? "N/A";
      final String lName = lData['fullName'] ?? "Landlord";
      final String lAadhaar = lData['aadharNumber'] ?? "N/A";

      final String panchayat = _pendingProp!['panchayatName'] ?? "N/A";
      final String blockNo = _pendingProp!['blockNo'] ?? "N/A";
      final String thandaperNo = _pendingProp!['thandaperNo'] ?? "N/A";
      final String rentAmount = _pendingProp!['rent'].toString();
      final String securityAmount = _pendingProp!['securityAmount'].toString();
      final String aptName =
          _pendingProp!['apartmentName'] ?? "Property #${_propertyIndex + 1}";

      final Uint8List? tSignBytes = await _fetchImageBytes(
        '$uid/sign/sign.jpg',
      );
      final Uint8List? lSignBytes = await _fetchImageBytes(
        '$_landlordUid/sign/sign.jpg',
      );
      final Uint8List? tPhotoBytes = await _fetchImageBytes(
        '$uid/profile_pic/',
        isListing: true,
      );
      final Uint8List? lPhotoBytes = await _fetchImageBytes(
        '$_landlordUid/profile_pic/',
        isListing: true,
      );

      if (tSignBytes == null || lSignBytes == null) {
        throw "Signatures are missing.";
      }

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
      DateTime endDateObj = DateTime(date.year, date.month + 11, date.day);
      final endDateStr =
          "${endDateObj.day}/${endDateObj.month}/${endDateObj.year}";

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
                          pw.Text("2. $tName (LESSEE/Tenant)"),
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
                      "Period of Tenancy: The tenancy is for a period of 11 months from $dateString to $endDateStr.",
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

      final Uint8List pdfBytes = await pdf.save();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = "agreement_$timestamp.pdf";

      await _uploadPdf(pdfBytes, 'lagreement/$_landlordUid/$fileName');
      await _uploadPdf(pdfBytes, 'tagreement/$uid/$fileName');

      // --- DAG INTEGRATION: SECURE THE AGREEMENT & GET HASH ---
      final String agreementJson = jsonEncode({
        "type": "Rental Agreement",
        "tenantUid": uid,
        "landlordUid": _landlordUid,
        "propertyIndex": _propertyIndex,
        "rentAmount": rentAmount,
        "securityAmount": securityAmount,
        "timestamp": timestamp,
      });

      // Mine the agreement node on the DAG and wait for the resulting cryptographic hash
      final String dagHash = await DagLedger.instance.addTransaction(
        agreementJson,
      );

      // --- APPEND THE DAG HASH TO THE AGREEMENT DB RECORD ---
      final agreementData = {
        'timestamp': timestamp,
        'date': dateString,
        'fileName': fileName,
        'landlordUid': _landlordUid,
        'landlordName': lName,
        'landlordAadhaar': lAadhaar,
        'tenantUid': uid,
        'tenantName': tName,
        'tenantAadhaar': tAadhaar,
        'apartmentName': aptName,
        'propertyIndex': _propertyIndex,
        'panchayat': panchayat,
        'blockNo': blockNo,
        'thandaperNo': thandaperNo,
        'rentAmount': rentAmount,
        'securityAmount': securityAmount,
        'dagHash': dagHash, // Secure pointer saved permanently in Firestore
      };

      await _saveAgreementRecords(agreementData);

      final tReqsMap = await _fetchDocData('trequests', uid);
      List<dynamic> tReqList = tReqsMap['requests'] ?? [];
      for (var req in tReqList) {
        if (req['luid'] == _landlordUid &&
            req['propertyIndex'] == _propertyIndex &&
            req['status'] == 'accepted') {
          req['status'] = 'completed';
          break;
        }
      }
      await _updateRequestStatus('trequests', uid, tReqList);

      final lReqsMap = await _fetchDocData('lrequests', _landlordUid);
      List<dynamic> lReqList = lReqsMap['requests'] ?? [];
      for (var req in lReqList) {
        if (req['tuid'] == uid &&
            req['propertyIndex'] == _propertyIndex &&
            req['status'] == 'accepted') {
          req['status'] = 'completed';
          break;
        }
      }
      await _updateRequestStatus('lrequests', _landlordUid, lReqList);

      await _updateHousePropertyStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Rental Agreement Generated Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error generating agreement: $e");
    }
  }

  // --- HYBRID HELPERS ---
  Future<Map<String, dynamic>> _fetchDocData(
    String col,
    String targetUid,
  ) async {
    if (_isNativeMobile) {
      final doc = await FirebaseFirestore.instance
          .collection(col)
          .doc(targetUid)
          .get();
      return doc.data() ?? {};
    } else {
      final url = Uri.parse(
        '$kFirestoreBaseUrl/$col/$targetUid?key=$kFirebaseAPIKey',
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

  Future<Uint8List?> _fetchImageBytes(
    String storagePath, {
    bool isListing = false,
  }) async {
    try {
      if (_isNativeMobile) {
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
        String targetPath = storagePath;
        if (isListing) {
          final listUrl = Uri.parse(
            '$kStorageBaseUrl?prefix=${Uri.encodeComponent(storagePath)}&key=$kFirebaseAPIKey',
          );
          final listResp = await http.get(listUrl);
          if (listResp.statusCode == 200) {
            final data = jsonDecode(listResp.body);
            if (data['items'] != null && (data['items'] as List).isNotEmpty) {
              targetPath = data['items'][0]['name'];
            } else {
              return null;
            }
          } else {
            return null;
          }
        }
        String encodedPath = Uri.encodeComponent(targetPath);
        final downloadUrl =
            '$kStorageBaseUrl/$encodedPath?alt=media&key=$kFirebaseAPIKey';
        final response = await http.get(Uri.parse(downloadUrl));
        if (response.statusCode == 200) return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _uploadPdf(Uint8List bytes, String path) async {
    if (_isNativeMobile) {
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
          "Authorization": "Bearer $token",
        },
        body: bytes,
      );
      if (response.statusCode != 200) throw "Upload Failed";
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

  Future<void> _saveAgreementRecords(Map<String, dynamic> agreementData) async {
    try {
      if (_isNativeMobile) {
        await FirebaseFirestore.instance
            .collection('lagreements')
            .doc(_landlordUid)
            .set({
              'agreements': FieldValue.arrayUnion([agreementData]),
            }, SetOptions(merge: true));
        await FirebaseFirestore.instance.collection('tagreements').doc(uid).set(
          {
            'agreements': FieldValue.arrayUnion([agreementData]),
          },
          SetOptions(merge: true),
        );
      } else {
        String? token = await FirebaseAuth.instance.currentUser?.getIdToken();
        final commitUrl = Uri.parse(
          '$kFirestoreBaseUrl:commit?key=$kFirebaseAPIKey',
        );
        final firestoreValue = _encodeMapForFirestore(agreementData);
        final body = jsonEncode({
          "writes": [
            {
              "transform": {
                "document":
                    "projects/$kProjectId/databases/(default)/documents/lagreements/$_landlordUid",
                "fieldTransforms": [
                  {
                    "fieldPath": "agreements",
                    "appendMissingElements": {
                      "values": [firestoreValue],
                    },
                  },
                ],
              },
            },
            {
              "transform": {
                "document":
                    "projects/$kProjectId/databases/(default)/documents/tagreements/$uid",
                "fieldTransforms": [
                  {
                    "fieldPath": "agreements",
                    "appendMissingElements": {
                      "values": [firestoreValue],
                    },
                  },
                ],
              },
            },
          ],
        });
        await http.post(
          commitUrl,
          body: body,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          },
        );
      }
    } catch (e) {
      debugPrint("Error saving agreement records: $e");
    }
  }

  Future<void> _updateRequestStatus(
    String collection,
    String targetUid,
    List<dynamic> updatedRequests,
  ) async {
    if (_isNativeMobile) {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(targetUid)
          .update({'requests': updatedRequests});
    } else {
      String? token = await FirebaseAuth.instance.currentUser?.getIdToken();
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
        '$kFirestoreBaseUrl/$collection/$targetUid?updateMask.fieldPaths=requests&key=$kFirebaseAPIKey',
      );
      await http.patch(
        url,
        body: jsonEncode({
          "fields": {"requests": jsonVal},
        }),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );
    }
  }

  Future<void> _updateHousePropertyStatus() async {
    try {
      if (_isNativeMobile) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('house')
            .doc(_landlordUid)
            .get();
        if (!doc.exists) return;
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<dynamic> properties = List.from(data['properties'] ?? []);
        if (_propertyIndex < properties.length) {
          properties[_propertyIndex]['status'] = 'occupied';
          await FirebaseFirestore.instance
              .collection('house')
              .doc(_landlordUid)
              .update({'properties': properties});
        }
      } else {
        final getUrl = Uri.parse(
          '$kFirestoreBaseUrl/house/$_landlordUid?key=$kFirebaseAPIKey',
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
                  .map((v) => requestsParseFirestoreValue(v))
                  .toList();
            }
          }
          if (_propertyIndex < properties.length) {
            properties[_propertyIndex]['status'] = 'occupied';
            List<Map<String, dynamic>> jsonValues = properties
                .map((p) => _encodeMapForFirestore(p))
                .toList();
            String? token = await FirebaseAuth.instance.currentUser
                ?.getIdToken();
            final patchUrl = Uri.parse(
              '$kFirestoreBaseUrl/house/$_landlordUid?updateMask.fieldPaths=properties&key=$kFirebaseAPIKey',
            );
            await http.patch(
              patchUrl,
              body: jsonEncode({
                "fields": {
                  "properties": {
                    "arrayValue": {"values": jsonValues},
                  },
                },
              }),
              headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer $token",
              },
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error updating property status: $e");
    }
  }

  // --- FETCHING HISTORY FOR WEB (HTTP) ---
  Future<List<Map<String, dynamic>>> _fetchHistoryWeb() async {
    try {
      final url = Uri.parse(
        '$kFirestoreBaseUrl/payments/$uid?key=$kFirebaseAPIKey',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['fields'] != null && json['fields']['payments'] != null) {
          final arrayValue = json['fields']['payments']['arrayValue'];
          if (arrayValue != null && arrayValue['values'] != null) {
            List<dynamic> values = arrayValue['values'];
            List<Map<String, dynamic>> parsedList = values.map((item) {
              if (item['mapValue'] != null &&
                  item['mapValue']['fields'] != null) {
                var fields = item['mapValue']['fields'];
                return {
                  'transId': fields['transId']?['stringValue'] ?? '',
                  'tenantName': fields['tenantName']?['stringValue'] ?? '',
                  'amount': fields['amount']?['stringValue'] ?? '',
                  'method': fields['method']?['stringValue'] ?? '',
                  'timestamp': fields['timestamp']?['stringValue'] ?? '',
                  'status': fields['status']?['stringValue'] ?? '',
                  'type': fields['type']?['stringValue'] ?? 'Payment',
                  'landlordUid': fields['landlordUid']?['stringValue'] ?? '',
                };
              }
              return <String, dynamic>{};
            }).toList();
            return parsedList.reversed.toList();
          }
        }
      }
    } catch (e) {
      debugPrint("Web Fetch Error: $e");
    }
    return [];
  }

  // ============================================================
  // MOCK SYSTEM ENTRY
  // ============================================================
  void _showMockPaymentSystem(String amount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return MockPaymentGateway(
          amount: amount,
          onSuccess: (txnId) async {
            await _savePaymentToFirestore(amount, txnId);

            if (_paymentMode == 'agreement') {
              await _generateAgreement();
            }
            await _checkPaymentStatus();

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Payment of ₹$amount Successful!"),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
        );
      },
    );
  }

  // --- RICH INVOICE RECEIPT LOGIC ---
  void _showReceiptDialog(Map<String, dynamic> transData) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _fetchPartyDetailsForReceipt(transData['landlordUid']),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.blue),
                      SizedBox(height: 15),
                      Text(
                        "Generating Receipt...",
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                );
              }

              final parties = snapshot.data ?? {};
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "PAYMENT RECEIPT",
                            style: TextStyle(
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.download,
                              color: Colors.blueAccent,
                            ),
                            onPressed: () =>
                                _downloadReceiptPdf(transData, parties),
                            tooltip: "Download PDF",
                          ),
                        ],
                      ),
                      const Divider(color: Colors.black26),
                      const SizedBox(height: 10),

                      // Details Section
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Your details (Tenant)",
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  parties['tenantName'] ?? "N/A",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  parties['tenantEmail'] ?? "N/A",
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  parties['tenantPhone'] ?? "N/A",
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Client's details (Landlord)",
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  parties['landlordName'] ?? "N/A",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  parties['landlordEmail'] ?? "N/A",
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  parties['landlordPhone'] ?? "N/A",
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Meta Info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Receipt No:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                transData['transId'],
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Receipt Date:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                _formatDate(transData['timestamp']),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Items Table Header
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.black26),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                "Item",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "Status",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "Subtotal",
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Item Row
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.black12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                transData['type'] ?? "Payment",
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                transData['status'] ?? "Success",
                                style: const TextStyle(color: Colors.green),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "INR ${transData['amount']}",
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Summary Section
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 200,
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  "Invoice Summary",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              const Divider(color: Colors.black26),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Total",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    "INR ${transData['amount']}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                          ),
                          child: const Text(
                            "Close",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchPartyDetailsForReceipt(
    String? lUid,
  ) async {
    Map<String, dynamic> result = {};
    try {
      // Fetch Tenant
      final tData = await _fetchDocData('tenant', uid);
      result['tenantName'] = tData['fullName'] ?? "Tenant";
      result['tenantEmail'] = tData['email'] ?? "N/A";
      result['tenantPhone'] = tData['phoneNumber'] ?? "N/A";

      // Fetch Landlord
      if (lUid != null && lUid.isNotEmpty) {
        final lData = await _fetchDocData('landlord', lUid);
        result['landlordName'] = lData['fullName'] ?? "Landlord";
        result['landlordEmail'] = lData['email'] ?? "N/A";
        result['landlordPhone'] = lData['phoneNumber'] ?? "N/A";
      }
    } catch (e) {
      debugPrint("Receipt data fetch error: $e");
    }
    return result;
  }

  Future<void> _downloadReceiptPdf(
    Map<String, dynamic> transData,
    Map<String, dynamic> parties,
  ) async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "PAYMENT RECEIPT",
                      style: pw.TextStyle(
                        color: PdfColors.blue,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "Your details (Tenant)",
                          style: pw.TextStyle(
                            color: PdfColors.blue,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          parties['tenantName'] ?? "N/A",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(parties['tenantEmail'] ?? "N/A"),
                        pw.Text(parties['tenantPhone'] ?? "N/A"),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "Client's details (Landlord)",
                          style: pw.TextStyle(
                            color: PdfColors.blue,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          parties['landlordName'] ?? "N/A",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(parties['landlordEmail'] ?? "N/A"),
                        pw.Text(parties['landlordPhone'] ?? "N/A"),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 30),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "Receipt No: ${transData['transId']}",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      "Date: ${_formatDate(transData['timestamp'])}",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.TableHelper.fromTextArray(
                  headers: ["Item", "Status", "Subtotal"],
                  data: [
                    [
                      transData['type'] ?? "Payment",
                      transData['status'] ?? "Success",
                      "INR ${transData['amount']}",
                    ],
                  ],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellAlignment: pw.Alignment.centerLeft,
                ),
                pw.SizedBox(height: 20),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "Invoice Summary",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        "Total: INR ${transData['amount']}",
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      final Uint8List pdfBytes = await pdf.save();
      final String fileName = "receipt_${transData['transId']}.pdf";
      final String uploadPath = '$uid/receipts/$fileName';

      await _uploadPdf(pdfBytes, uploadPath);

      // Generate Download Link
      String downloadUrl = "";
      if (_isNativeMobile) {
        downloadUrl = await FirebaseStorage.instance
            .ref(uploadPath)
            .getDownloadURL();
      } else {
        String encodedPath = Uri.encodeComponent(uploadPath);
        downloadUrl =
            '$kStorageBaseUrl/$encodedPath?alt=media&key=$kFirebaseAPIKey';
      }

      if (await canLaunchUrl(Uri.parse(downloadUrl))) {
        await launchUrl(
          Uri.parse(downloadUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint("PDF Download Error: $e");
    }
  }

  String _formatDate(String dateStr) {
    try {
      DateTime dt = DateTime.parse(dateStr);
      return "${dt.day}-${dt.month}-${dt.year}";
    } catch (e) {
      return dateStr;
    }
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    bool canShowHistory = (uid.isNotEmpty);

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
                  title: "Payments",
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 15),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- DYNAMIC PAYMENT SECTION ---
                        if (_paymentMode == 'loading')
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        else if (_paymentMode == 'none')
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 40,
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    "No due rent",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _paymentMode == 'agreement'
                                        ? "Complete Agreement"
                                        : "Due Rent",
                                    style: TextStyle(
                                      color: Colors.orange.shade300,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _paymentMode == 'agreement'
                                        ? "Pay the amount of rent + security amount to complete the agreement."
                                        : "Your monthly rent is due.",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Breakdown breakdown
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              "Rent Amount",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              "₹${_rentAmount.toInt()}",
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_paymentMode == 'agreement') ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text(
                                                "Security Deposit",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              Text(
                                                "₹${_secAmount.toInt()}",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        const Divider(
                                          color: Colors.white24,
                                          height: 20,
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              "Total Due",
                                              style: TextStyle(
                                                color: Colors.greenAccent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              "₹${_dueAmount.toInt()}",
                                              style: const TextStyle(
                                                color: Colors.greenAccent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _isProcessing
                                          ? null
                                          : _handlePaymentClick,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      child: _isProcessing
                                          ? const CircularProgressIndicator(
                                              color: Colors.white,
                                            )
                                          : Text(
                                              "Pay ₹${_dueAmount.toInt()}",
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(height: 35),
                        Text(
                          "Transaction History",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // --- HISTORY LIST ---
                        if (canShowHistory)
                          _isNativeMobile
                              ? StreamBuilder<DocumentSnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('payments')
                                      .doc(uid)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                      );
                                    }
                                    if (!snapshot.hasData ||
                                        !snapshot.data!.exists) {
                                      return Center(
                                        child: Text(
                                          "No transactions found.",
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    var docData =
                                        snapshot.data!.data()
                                            as Map<String, dynamic>;
                                    List<dynamic> payments =
                                        docData['payments'] ?? [];
                                    if (payments.isEmpty) {
                                      return Center(
                                        child: Text(
                                          "No transactions found.",
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return _buildHistoryList(
                                      payments.reversed.toList(),
                                    );
                                  },
                                )
                              : FutureBuilder<List<Map<String, dynamic>>>(
                                  future: _fetchHistoryWeb(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                      );
                                    }
                                    if (!snapshot.hasData ||
                                        snapshot.data!.isEmpty) {
                                      return Center(
                                        child: Text(
                                          "No transactions found.",
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return _buildHistoryList(snapshot.data!);
                                  },
                                ),

                        const SizedBox(height: 60),
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

  Widget _buildHistoryList(List<dynamic> payments) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        var data = payments[index] as Map<String, dynamic>;
        return GestureDetector(
          onTap: () => _showReceiptDialog(data),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
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
                    "₹${data['amount']} - ${data['type'] ?? 'Payment'}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _formatDate(data['timestamp'] ?? DateTime.now().toString()),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  trailing: Text(
                    data['status'] ?? 'Success',
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =======================================================================
//  MOCK PAYMENT GATEWAY (WEB/DESKTOP)
// =======================================================================

class MockPaymentGateway extends StatefulWidget {
  final String amount;
  final Function(String txnId) onSuccess;

  const MockPaymentGateway({
    super.key,
    required this.amount,
    required this.onSuccess,
  });

  @override
  State<MockPaymentGateway> createState() => _MockPaymentGatewayState();
}

class _MockPaymentGatewayState extends State<MockPaymentGateway> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();
  final TextEditingController _holderController = TextEditingController();

  bool _isProcessing = false;
  String? _cardType;

  String? _detectCardType(String number) {
    String clean = number.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return null;
    if (clean.startsWith('4')) return 'Visa';
    if (RegExp(r'^5[1-5]').hasMatch(clean) ||
        RegExp(
          r'^2(?:2(?:2[1-9]|[3-9]\d)|[3-6]\d\d|7(?:[01]\d|20))',
        ).hasMatch(clean)) {
      return 'Mastercard';
    }
    if (RegExp(r'^3[47]').hasMatch(clean)) return 'Amex';
    if (RegExp(r'^3(?:0[0-5]|[68])').hasMatch(clean)) return 'Diners Club';
    if (RegExp(r'^6(?:0|521|522)').hasMatch(clean)) return 'RuPay';
    if (RegExp(r'^35(?:2[89]|[3-8]\d)').hasMatch(clean)) return 'JCB';
    if (RegExp(r'^62').hasMatch(clean)) return 'UnionPay';
    return null;
  }

  bool _checkLuhn(String number) {
    String clean = number.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 8) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = clean.length - 1; i >= 0; i--) {
      int n = int.parse(clean.substring(i, i + 1));
      if (alternate) {
        n *= 2;
        if (n > 9) n = (n % 10) + 1;
      }
      sum += n;
      alternate = !alternate;
    }
    return (sum % 10 == 0);
  }

  Future<void> _processMockPayment() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      String txnId =
          "txn_web_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(4294967295)}";
      Navigator.pop(context);
      widget.onSuccess(txnId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Secure Payment",
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "Total Amount to Pay",
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "₹${widget.amount}",
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),

                TextFormField(
                  controller: _cardNumberController,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(19),
                    _CardNumberFormatter(),
                  ],
                  decoration: InputDecoration(
                    labelText: "Card Number",
                    labelStyle: TextStyle(
                      color: Colors.black.withValues(alpha: 0.7),
                    ),
                    hintText: "0000 0000 0000 0000",
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.credit_card),
                    suffixIcon: _cardType != null
                        ? Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: _buildCardLogo(_cardType!),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 8.0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Visa • MC • Amex • RuPay",
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "Diners • JCB • UnionPay",
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  onChanged: (val) =>
                      setState(() => _cardType = _detectCardType(val)),
                  validator: (val) {
                    if (val == null || val.isEmpty) return "Required";
                    String clean = val.replaceAll(RegExp(r'\D'), '');
                    if (clean.length < 13) return "Invalid length";
                    if (!_checkLuhn(val)) return "Invalid card number";
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _holderController,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: "Card Holder Name",
                    labelStyle: TextStyle(
                      color: Colors.black.withValues(alpha: 0.7),
                    ),
                    prefixIcon: const Icon(Icons.person),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (val) => (val == null || val.length < 3)
                      ? "Enter valid name"
                      : null,
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _expiryController,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                          _ExpiryDateFormatter(),
                        ],
                        decoration: InputDecoration(
                          labelText: "Expiry (MM/YY)",
                          labelStyle: TextStyle(
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                          hintText: "MM/YY",
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(
                            Icons.calendar_today,
                            size: 20,
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length != 5) return "Invalid";
                          if (!val.contains('/')) return "Use MM/YY";
                          int month = int.tryParse(val.substring(0, 2)) ?? 0;
                          int year = int.tryParse(val.substring(3, 5)) ?? 0;
                          if (month < 1 || month > 12) return "Bad Month";
                          final now = DateTime.now();
                          final currentYear = int.parse(
                            now.year.toString().substring(2),
                          );
                          final currentMonth = now.month;
                          if (year < currentYear) return "Expired";
                          if (year == currentYear && month < currentMonth) {
                            return "Expired";
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _cvvController,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: InputDecoration(
                          labelText: "CVV",
                          labelStyle: TextStyle(
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                          hintText: "123",
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        ),
                        validator: (val) => (val == null || val.length != 3)
                            ? "3 Digits"
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _processMockPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            "Pay ₹${widget.amount}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.lock, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Text(
                        "Secure Payment Gateway",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardLogo(String type) {
    Color color = Colors.black;
    if (type == 'Visa') color = Colors.blue;
    if (type == 'Mastercard') color = Colors.orange;
    if (type == 'Amex') color = Colors.cyan;
    if (type == 'RuPay') color = Colors.green;
    if (type == 'Diners Club') color = Colors.blueGrey;
    if (type == 'JCB') color = Colors.red;
    if (type == 'UnionPay') color = Colors.teal;
    return Text(
      type,
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }
}

// --- FORMATTERS ---
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) {
        buffer.write(' ');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var newText = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;
    var buffer = StringBuffer();
    for (int i = 0; i < newText.length; i++) {
      buffer.write(newText[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != newText.length) {
        buffer.write('/');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}
