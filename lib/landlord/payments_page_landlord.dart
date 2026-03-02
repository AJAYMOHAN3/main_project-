import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/config.dart';

class PaymentsPage extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage({super.key, required this.onBack});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _fetchedPayments = [];

  bool get _isNativeMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _fetchLandlordPayments();
  }

  // --- FETCH ALL PAYMENTS FOR THIS LANDLORD ---
  Future<void> _fetchLandlordPayments() async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> allPayments = [];

    try {
      // 1. SDK LOGIC (Android/iOS)
      if (_isNativeMobile) {
        final QuerySnapshot snapshot = await FirebaseFirestore.instance
            .collection('payments')
            .get();

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('payments')) {
            List<dynamic> paymentsArr = data['payments'];
            for (var p in paymentsArr) {
              if (p is Map<String, dynamic> && p['landlordUid'] == uid) {
                // Store the payment data AND the doc ID (which is the tenantUid)
                Map<String, dynamic> paymentData = Map<String, dynamic>.from(p);
                paymentData['tenantUid'] = doc.id;
                allPayments.add(paymentData);
              }
            }
          }
        }
      }
      // 2. REST LOGIC (Web/Desktop)
      else {
        final url = Uri.parse(
          '$kFirestoreBaseUrl/payments?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['documents'] != null) {
            for (var doc in data['documents']) {
              String docName = doc['name'];
              String docId = docName.split('/').last; // This is the tenantUid

              if (doc['fields'] != null && doc['fields']['payments'] != null) {
                var rawList =
                    doc['fields']['payments']['arrayValue']['values'] as List?;
                if (rawList != null) {
                  for (var item in rawList) {
                    if (item['mapValue'] != null &&
                        item['mapValue']['fields'] != null) {
                      Map<String, dynamic> cleanMap = {};
                      item['mapValue']['fields'].forEach((k, v) {
                        cleanMap[k] = _parseFirestoreRestValue(v);
                      });

                      if (cleanMap['landlordUid'] == uid) {
                        cleanMap['tenantUid'] = docId; // Store tenant doc ID
                        allPayments.add(cleanMap);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Sort payments by timestamp descending (newest first)
      allPayments.sort((a, b) {
        DateTime timeA =
            DateTime.tryParse(a['timestamp'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        DateTime timeB =
            DateTime.tryParse(b['timestamp'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return timeB.compareTo(timeA);
      });
    } catch (e) {
      debugPrint("Error fetching landlord payments: $e");
    }

    if (mounted) {
      setState(() {
        _fetchedPayments = allPayments;
        _isLoading = false;
      });
    }
  }

  // --- HELPER TO FETCH SPECIFIC DOCUMENT DATA ---
  Future<Map<String, dynamic>> _fetchDocData(
    String collection,
    String targetUid,
  ) async {
    if (_isNativeMobile) {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(targetUid)
          .get();
      return doc.data() ?? {};
    } else {
      final url = Uri.parse(
        '$kFirestoreBaseUrl/$collection/$targetUid?key=$kFirebaseAPIKey',
      );
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['fields'] != null) {
          Map<String, dynamic> res = {};
          data['fields'].forEach((k, v) {
            res[k] = _parseFirestoreRestValue(v);
          });
          return res;
        }
      }
      return {};
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
    return null;
  }

  // --- FETCH PARTY DETAILS FOR RECEIPT ---
  Future<Map<String, dynamic>> _fetchPartyDetailsForReceipt(
    String? tenantUid,
  ) async {
    Map<String, dynamic> result = {};
    try {
      // Fetch Landlord (Current User)
      final lData = await _fetchDocData('landlord', uid);
      result['landlordName'] = lData['fullName'] ?? "Landlord";
      result['landlordEmail'] = lData['email'] ?? "N/A";
      result['landlordPhone'] = lData['phoneNumber'] ?? "N/A";

      // Fetch Tenant (Using the stored docId)
      if (tenantUid != null && tenantUid.isNotEmpty) {
        final tData = await _fetchDocData('tenant', tenantUid);
        result['tenantName'] = tData['fullName'] ?? "Tenant";
        result['tenantEmail'] = tData['email'] ?? "N/A";
        result['tenantPhone'] = tData['phoneNumber'] ?? "N/A";
      } else {
        result['tenantName'] = "Unknown Tenant";
        result['tenantEmail'] = "N/A";
        result['tenantPhone'] = "N/A";
      }
    } catch (e) {
      debugPrint("Receipt data fetch error: $e");
    }
    return result;
  }

  // --- RICH INVOICE RECEIPT LOGIC ---
  void _showReceiptDialog(Map<String, dynamic> transData) {
    List<Widget> itemRows = [];
    double totalAmount = double.tryParse(transData['amount'].toString()) ?? 0.0;
    double rentAmt =
        double.tryParse(transData['rentAmount']?.toString() ?? '0') ?? 0.0;
    double secAmt =
        double.tryParse(transData['securityAmount']?.toString() ?? '0') ?? 0.0;

    if (rentAmt == 0 &&
        secAmt == 0 &&
        transData['type'] == 'Agreement Payment') {
      rentAmt = totalAmount;
    }

    if (transData['type'] == 'Agreement Payment') {
      itemRows.addAll([
        _buildReceiptItemRow("Security Deposit", "Success", secAmt),
        const SizedBox(height: 8),
        _buildReceiptItemRow("1st Month Rent", "Success", rentAmt),
      ]);
    } else {
      itemRows.add(
        _buildReceiptItemRow("Monthly Rent", "Success", totalAmount),
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 24.0,
          ),
          child: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<Map<String, dynamic>>(
              // Pass the stored tenantUid here
              future: _fetchPartyDetailsForReceipt(transData['tenantUid']),
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
                    padding: const EdgeInsets.all(16.0),
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
                                fontSize: 18,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.print,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () =>
                                  _viewAndSaveReceiptPdf(transData, parties),
                              tooltip: "View PDF",
                            ),
                          ],
                        ),
                        const Divider(color: Colors.black26),
                        const SizedBox(height: 10),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Client's details (Tenant)",
                                    style: TextStyle(
                                      color: Colors.blueAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    parties['tenantName'] ?? "N/A",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    parties['tenantEmail'] ?? "N/A",
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    parties['tenantPhone'] ?? "N/A",
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Your details (Landlord)",
                                    style: TextStyle(
                                      color: Colors.blueAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    parties['landlordName'] ?? "N/A",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    parties['landlordEmail'] ?? "N/A",
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    parties['landlordPhone'] ?? "N/A",
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Receipt No:",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    transData['transId'] ?? 'N/A',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  "Receipt Date:",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _formatDate(transData['timestamp'] ?? ''),
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

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
                                    fontSize: 13,
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
                                    fontSize: 13,
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
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.black12),
                            ),
                          ),
                          child: Column(children: itemRows),
                        ),
                        const SizedBox(height: 20),

                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 180,
                            child: Column(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8.0),
                                  child: Text(
                                    "Invoice Summary",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 13,
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
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      "INR ${transData['amount']}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                        fontSize: 14,
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
          ),
        );
      },
    );
  }

  Widget _buildReceiptItemRow(String itemName, String status, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            itemName,
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            status,
            style: const TextStyle(color: Colors.green, fontSize: 12),
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            "INR ${amount.toInt()}",
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _viewAndSaveReceiptPdf(
    Map<String, dynamic> transData,
    Map<String, dynamic> parties,
  ) async {
    try {
      final pdf = pw.Document();

      List<List<String>> tableData = [];
      double totalAmount =
          double.tryParse(transData['amount'].toString()) ?? 0.0;
      double rentAmt =
          double.tryParse(transData['rentAmount']?.toString() ?? '0') ?? 0.0;
      double secAmt =
          double.tryParse(transData['securityAmount']?.toString() ?? '0') ??
          0.0;

      if (rentAmt == 0 &&
          secAmt == 0 &&
          transData['type'] == 'Agreement Payment') {
        rentAmt = totalAmount;
      }

      if (transData['type'] == 'Agreement Payment') {
        tableData.add(["Security Deposit", "Success", "INR ${secAmt.toInt()}"]);
        tableData.add(["1st Month Rent", "Success", "INR ${rentAmt.toInt()}"]);
      } else {
        tableData.add([
          "Monthly Rent",
          "Success",
          "INR ${totalAmount.toInt()}",
        ]);
      }

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
                          "Client's details (Tenant)",
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
                          "Your details (Landlord)",
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
                      "Receipt No: ${transData['transId'] ?? 'N/A'}",
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                    pw.Text(
                      "Date: ${_formatDate(transData['timestamp'] ?? '')}",
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.TableHelper.fromTextArray(
                  headers: ["Item", "Status", "Subtotal"],
                  data: tableData,
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

      if (_isNativeMobile) {
        final directory = await getApplicationDocumentsDirectory();
        final File localFile = File('${directory.path}/$fileName');
        await localFile.writeAsBytes(pdfBytes);
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: const Text(
                  "Receipt Preview",
                  style: TextStyle(color: Colors.white),
                ),
                iconTheme: const IconThemeData(color: Colors.white),
                backgroundColor: const Color(0xFF1E1E2C),
              ),
              body: PdfPreview(
                build: (format) => pdfBytes,
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("PDF Viewing Error: $e");
    }
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return "N/A";
    try {
      DateTime dt = DateTime.parse(dateStr);
      return "${dt.day}-${dt.month}-${dt.year}";
    } catch (e) {
      return dateStr;
    }
  }

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

                        _isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.orange,
                                  ),
                                ),
                              )
                            : _fetchedPayments.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Center(
                                  child: Text(
                                    "No transactions found.",
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                itemCount: _fetchedPayments.length,
                                itemBuilder: (context, index) {
                                  var data = _fetchedPayments[index];
                                  return GestureDetector(
                                    onTap: () => _showReceiptDialog(data),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                      child: ListTile(
                                        leading: Icon(
                                          Icons.receipt_long,
                                          color: Colors.orange.shade400,
                                        ),
                                        title: Text(
                                          "₹${data['amount']} - ${data['tenantName'] ?? 'Tenant'}",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          "${_formatDate(data['timestamp'] ?? '')} • ${data['type'] ?? 'Payment'}",
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.7,
                                            ),
                                          ),
                                        ),
                                        trailing: Text(
                                          data['status'] ?? 'Success',
                                          style: TextStyle(
                                            color: data['status'] == "Success"
                                                ? Colors.greenAccent
                                                : Colors.orangeAccent,
                                          ),
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
}
