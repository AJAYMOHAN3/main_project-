import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';

class PaymentsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage2({super.key, required this.onBack});

  @override
  State<PaymentsPage2> createState() => _PaymentsPage2State();
}

class _PaymentsPage2State extends State<PaymentsPage2> {
  String? selectedMethod;
  final TextEditingController _amountController = TextEditingController();

  // Mock transactions
  final List<Map<String, dynamic>> mockTransactions = [
    {
      'amount': 499,
      'method': 'UPI',
      'date': '18 Oct 2025, 10:45 AM',
      'status': 'Success',
    },
    {
      'amount': 799,
      'method': 'Credit Card',
      'date': '15 Oct 2025, 2:22 PM',
      'status': 'Pending',
    },
    {
      'amount': 299,
      'method': 'Net Banking',
      'date': '10 Oct 2025, 9:10 PM',
      'status': 'Success',
    },
  ];

  @override
  Widget build(BuildContext context) {
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
                                  "Choose your payment method (India):",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Payment method buttons
                                Wrap(
                                  spacing: 10,
                                  children: [
                                    _paymentButton(
                                      "UPI",
                                      Icons.account_balance_wallet,
                                    ),
                                    _paymentButton(
                                      "Credit/Debit Card",
                                      Icons.credit_card,
                                    ),
                                    _paymentButton(
                                      "Net Banking",
                                      Icons.account_balance,
                                    ),
                                    _paymentButton("Wallets", Icons.wallet),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Dynamic payment fields
                                if (selectedMethod != null)
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: _buildPaymentFields(selectedMethod!),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),
                        // -------------------- TRANSACTION HISTORY --------------------
                        Text(
                          "Transaction History",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: mockTransactions.length,
                          itemBuilder: (context, index) {
                            var data = mockTransactions[index];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
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
                                      "₹${data['amount']} - ${data['method']}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      data['date'],
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                    trailing: Text(
                                      data['status'],
                                      style: TextStyle(
                                        color: data['status'] == "Success"
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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

  // -------------------- PAYMENT BUTTON --------------------
  Widget _paymentButton(String title, IconData icon) {
    final bool isSelected = selectedMethod == title;
    return ElevatedButton.icon(
      onPressed: () => setState(() => selectedMethod = title),
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(title, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Colors.orange.shade700
            : Colors.white.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // -------------------- PAYMENT FIELDS --------------------
  Widget _buildPaymentFields(String method) {
    switch (method) {
      case "UPI":
        return Column(
          key: const ValueKey("UPI"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Enter UPI ID (e.g. name@okaxis)"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Credit/Debit Card":
        return Column(
          key: const ValueKey("Card"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Card Number"),
            const SizedBox(height: 10),
            _textField("Card Holder Name"),
            const SizedBox(height: 10),
            _textField("Expiry (MM/YY)"),
            const SizedBox(height: 10),
            _textField("CVV", obscure: true),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Net Banking":
        return Column(
          key: const ValueKey("NetBanking"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Bank Name"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Wallets":
        return Column(
          key: const ValueKey("Wallets"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Wallet Name (Paytm, PhonePe, etc.)"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // -------------------- SHARED INPUTS --------------------
  Widget _textField(String hint, {bool obscure = false}) {
    return TextField(
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
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

  Widget _proceedButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: ElevatedButton(
        onPressed: () {
          String amount = _amountController.text.trim();
          if (amount.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please enter an amount")),
            );
            return;
          }

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E2A47),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text(
                "Confirm Payment",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                "Are you sure you want to proceed with ₹$amount via $selectedMethod?",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Payment of ₹$amount initiated via $selectedMethod",
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    "Confirm",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Center(
          child: Text(
            "Proceed to Pay",
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
