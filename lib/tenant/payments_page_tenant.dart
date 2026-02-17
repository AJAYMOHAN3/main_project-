import 'dart:convert';
import 'dart:io'; // Required for Platform check
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for input formatters
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:main_project/config.dart';
import 'dart:math';

class PaymentsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage2({super.key, required this.onBack});

  @override
  State<PaymentsPage2> createState() => _PaymentsPage2State();
}

class _PaymentsPage2State extends State<PaymentsPage2> {
  final TextEditingController _amountController = TextEditingController();
  bool _isProcessing = false;

  // Helper to determine if we are on Native Mobile (Android/iOS)
  bool get _isNativeMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    // 1. SAFE INITIALIZATION
    if (_isNativeMobile) {
      Stripe.publishableKey = stripePublishableKey;
    }
  }

  // --- PAYMENT LOGIC ---

  Future<void> _makePayment() async {
    String amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter an amount")));
      return;
    }

    setState(() => _isProcessing = true);

    if (_isNativeMobile) {
      // ----------------------------------------------------------
      // EXISTING STRIPE MOBILE CODE (UNTOUCHED LOGIC)
      // ----------------------------------------------------------
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
      // ----------------------------------------------------------
      // MOCK SYSTEM FOR WEB/DESKTOP/LINUX
      // ----------------------------------------------------------
      setState(() => _isProcessing = false);
      _showMockPaymentSystem(amountStr);
    }
  }

  // --- MOBILE ONLY HELPER: DISPLAY SHEET ---
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
        _amountController.clear();
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

  // --- MOBILE ONLY HELPER: CREATE INTENT ---
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

  // --- SAVING DATA (HYBRID: SDK for Mobile, REST for Web/Desktop) ---
  Future<void> _savePaymentToFirestore(String amount, String paymentId) async {
    String tenantName = "Unknown";
    String timestamp = DateTime.now().toString();
    String method = _isNativeMobile ? 'Stripe Card' : 'Card (Web/Desktop)';

    try {
      if (_isNativeMobile) {
        // --- 1. MOBILE: USE SDK ---

        // Fetch Tenant Name
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
        };

        // Save
        await FirebaseFirestore.instance.collection('payments').doc(uid).set({
          'payments': FieldValue.arrayUnion([paymentData]),
        }, SetOptions(merge: true));
      } else {
        // --- 2. WEB/DESKTOP: USE HTTP REST API ---

        // A. Fetch Tenant Name via HTTP
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

        // B. Prepare JSON for ArrayUnion using 'transform' (commit)
        // We must map Dart types to Firestore JSON types explicitly
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

        final resp = await http.post(
          commitUrl,
          body: body,
          headers: {'Content-Type': 'application/json'},
        );
        if (resp.statusCode != 200) {
          debugPrint("Error saving payment via HTTP: ${resp.body}");
        }
      }
    } catch (e) {
      debugPrint("Error saving payment: $e");
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

            // Map Firestore JSON to Simple Map
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
                };
              }
              return <String, dynamic>{};
            }).toList();

            // Reverse to show newest first
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
            _amountController.clear();

            // Trigger UI update for Web since we aren't using a stream
            setState(() {});

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

  // --- RECEIPT UI ---
  void _showReceiptDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    "PAYMENT RECEIPT",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const Divider(color: Colors.black26, height: 30),
                _receiptRow("Transaction ID", data['transId']),
                const SizedBox(height: 8),
                _receiptRow("Tenant Name", data['tenantName']),
                const SizedBox(height: 8),
                _receiptRow("Amount Paid", "₹${data['amount']}"),
                const SizedBox(height: 8),
                _receiptRow("Payment Method", data['method'] ?? 'Card'),
                const SizedBox(height: 8),
                _receiptRow("Date & Time", _formatDate(data['timestamp'])),
                const SizedBox(height: 8),
                _receiptRow("Status", data['status'] ?? "Success"),
                const SizedBox(height: 20),
                Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Close"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _receiptRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120, // Slightly wider for labels
          child: Text(
            "$label:",
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(String dateStr) {
    try {
      DateTime dt = DateTime.parse(dateStr);
      return "${dt.day}-${dt.month}-${dt.year} ${dt.hour}:${dt.minute}";
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
                        // --- INPUT SECTION ---
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Make a Payment",
                                  style: TextStyle(
                                    color: Colors.orange.shade300,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "Payment Method:",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {},
                                    icon: const Icon(
                                      Icons.credit_card,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      "Credit / Debit Card",
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.shade700,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _amountField(),
                                Padding(
                                  padding: const EdgeInsets.only(top: 15.0),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _isProcessing
                                          ? null
                                          : _makePayment,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
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
                                              "Pay Now",
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),
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
                    "₹${data['amount']} - ${data['method'] ?? 'Card'}",
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

  Widget _amountField() {
    return TextField(
      controller: _amountController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Enter Amount (₹)",
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

// =======================================================================
//  MOCK PAYMENT GATEWAY (WEB/DESKTOP)
//  Includes: Mod10/Luhn Algorithm, Range Check, Future Date, Auto-Format
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

  // --- 1. CARD NETWORK REGEX ---
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

  // --- 2. LUHN ALGORITHM ---
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

  // --- 3. SUBMIT LOGIC ---
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

                // CARD NUMBER (BLACK TEXT)
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

                // NAME (BLACK TEXT)
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

                // EXPIRY & CVV (BLACK TEXT)
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

                // PAY BUTTON
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
