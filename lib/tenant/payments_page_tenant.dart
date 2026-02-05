import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';

class PaymentsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage2({super.key, required this.onBack});

  @override
  State<PaymentsPage2> createState() => _PaymentsPage2State();
}

class _PaymentsPage2State extends State<PaymentsPage2> {
  // --- STRIPE KEYS ---
  final String stripePublishableKey = "";
  final String stripeSecretKey = "";

  final TextEditingController _amountController = TextEditingController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Initialize Stripe
    Stripe.publishableKey = stripePublishableKey;
  }

  // --- STRIPE LOGIC ---

  Future<void> _makePayment() async {
    String amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter an amount")));
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // 1. Create Payment Intent
      final paymentIntentData = await _createPaymentIntent(amountStr, 'INR');

      // CAPTURE PAYMENT ID
      final String paymentId = paymentIntentData['id'];

      // 2. Initialize Payment Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntentData['client_secret'],
          merchantDisplayName: 'Secure Homes',
          style: ThemeMode.dark, // Matches your app theme
        ),
      );

      // 3. Display Payment Sheet (Pass the ID)
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
  }

  Future<void> _displayPaymentSheet(String amount, String paymentId) async {
    try {
      await Stripe.instance.presentPaymentSheet().then((value) async {
        // SUCCESS
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Payment of ₹$amount Successful!"),
              backgroundColor: Colors.green,
            ),
          );
        }

        // --- 1. STORE TO FIRESTORE ---
        await _savePaymentToFirestore(amount, paymentId);

        _amountController.clear();
      });
    } on StripeException catch (_) {
      // CANCELLED / FAILED
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

  Future<void> _savePaymentToFirestore(String amount, String paymentId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final paymentData = {
      'transId': paymentId,
      'amount': amount,
      'tenantName': user.displayName ?? 'Unknown',
      'timestamp': DateTime.now().toString(),
      'method': 'Stripe Card',
      'status': 'Success',
    };

    try {
      await FirebaseFirestore.instance.collection('payments').doc(user.uid).set(
        {
          'payments': FieldValue.arrayUnion([paymentData]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint("Error saving payment: $e");
    }
  }

  Future<Map<String, dynamic>> _createPaymentIntent(
    String amount,
    String currency,
  ) async {
    try {
      // Stripe expects amount in smallest currency unit (e.g., paise for INR)
      // 100 INR = 10000 paise
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

  // --- 3. RECEIPT UI ---
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
                _receiptRow("Date & Time", _formatDate(data['timestamp'])),
                const SizedBox(height: 8),
                _receiptRow("Status", "Success"),
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
          width: 110,
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
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---------- TOP NAV BAR ----------
                CustomTopNavBar(
                  showBack: true,
                  title: "Payments",
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 15),

                // ---------- SCROLLABLE CONTENT ----------
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // -------------------- PAYMENT SETUP --------------------
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

                                // ONLY CARD OPTION AS REQUESTED
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {}, // Selected by default
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

                                // --- AMOUNT INPUT ---
                                _amountField(),

                                // --- PROCEED BUTTON ---
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
                                              "Pay Now with Stripe",
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
                        // -------------------- TRANSACTION HISTORY (REAL-TIME) --------------------
                        Text(
                          "Transaction History",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 2. FETCH AND DISPLAY FROM FIRESTORE
                        if (user != null)
                          StreamBuilder<DocumentSnapshot>(
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

                              if (!snapshot.hasData || !snapshot.data!.exists) {
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
                                  snapshot.data!.data() as Map<String, dynamic>;
                              List<dynamic> payments =
                                  docData['payments'] ?? [];
                              // Show newest first
                              var reversedList = payments.reversed.toList();

                              if (reversedList.isEmpty) {
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

                              return ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: reversedList.length,
                                itemBuilder: (context, index) {
                                  var data =
                                      reversedList[index]
                                          as Map<String, dynamic>;

                                  return GestureDetector(
                                    onTap: () {
                                      // 3. SHOW RECEIPT
                                      _showReceiptDialog(data);
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: 10,
                                          sigmaY: 10,
                                        ),
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                              "₹${data['amount']} - ${data['method'] ?? 'Card'}",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            subtitle: Text(
                                              _formatDate(
                                                data['timestamp'] ??
                                                    DateTime.now().toString(),
                                              ),
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.7,
                                                ),
                                              ),
                                            ),
                                            trailing: Text(
                                              data['status'] ?? 'Success',
                                              style: const TextStyle(
                                                color: Colors.greenAccent,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
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
