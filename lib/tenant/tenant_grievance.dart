import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Import your custom UI components
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';

// =======================================================================
//  1. TENANT GRIEVANCE LIST PAGE (Shows all apartments)
// =======================================================================

class TenantGrievancePage extends StatefulWidget {
  const TenantGrievancePage({super.key});

  @override
  State<TenantGrievancePage> createState() => _TenantGrievancePageState();
}

class _TenantGrievancePageState extends State<TenantGrievancePage> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const AnimatedGradientBackground(), // Background added
          SafeArea(
            child: Column(
              children: [
                // Custom Top Nav Bar applied
                CustomTopNavBar(
                  showBack: true,
                  title: "My Grievances",
                  onBack: () => Navigator.pop(context),
                ),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('tagreements')
                        .doc(_uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return const Center(
                          child: Text(
                            "No active agreements found.",
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      var data = snapshot.data!.data() as Map<String, dynamic>;
                      List<dynamic> agreements = data['agreements'] ?? [];

                      if (agreements.isEmpty) {
                        return const Center(
                          child: Text(
                            "No active properties to report grievances for.",
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: agreements.length,
                        itemBuilder: (context, index) {
                          var agreement = agreements[index];
                          return _buildLandlordCard(
                            agreement['landlordUid'] ?? "",
                            agreement['apartmentName'] ?? "Unknown Apartment",
                          );
                        },
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

  Widget _buildLandlordCard(String landlordUid, String apartmentName) {
    return Card(
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        leading: const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.business, color: Colors.white),
        ),
        title: Text(
          apartmentName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text(
          "Tap to view grievance chat",
          style: TextStyle(color: Colors.white60),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.white24,
          size: 16,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GrievanceChatPage(
                landlordUid: landlordUid,
                apartmentName: apartmentName,
                tenantUid: _uid,
              ),
            ),
          );
        },
      ),
    );
  }
}

// =======================================================================
//  2. TENANT CHAT PAGE (The actual chat room)
// =======================================================================

class GrievanceChatPage extends StatefulWidget {
  final String landlordUid;
  final String apartmentName;
  final String tenantUid;

  const GrievanceChatPage({
    super.key,
    required this.landlordUid,
    required this.apartmentName,
    required this.tenantUid,
  });

  @override
  State<GrievanceChatPage> createState() => _GrievanceChatPageState();
}

class _GrievanceChatPageState extends State<GrievanceChatPage> {
  final TextEditingController _messageController = TextEditingController();

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final newMessage = {
      "s": "t", // 't' for tenant sender
      "msg": _messageController.text.trim(),
      "time": DateTime.now().toIso8601String(),
    };

    // Reference path: grievances/tenantUid/landlords/landlordUid
    final docRef = FirebaseFirestore.instance
        .collection('grievances')
        .doc(widget.tenantUid)
        .collection('landlords')
        .doc(widget.landlordUid);

    await docRef.set({
      "apartmentName": widget.apartmentName,
      "status": "Open",
      "participants": {"t": widget.tenantUid, "l": widget.landlordUid},
      "messages": FieldValue.arrayUnion([newMessage]),
    }, SetOptions(merge: true));

    _messageController.clear();
  }

  void _closeGrievance() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        title: const Text(
          "Close Grievance?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "This will mark the issue as resolved and disable further chatting.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Resolve", style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('grievances')
          .doc(widget.tenantUid)
          .collection('landlords')
          .doc(widget.landlordUid)
          .update({"status": "Resolved"});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const AnimatedGradientBackground(), // Background added
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('grievances')
                  .doc(widget.tenantUid)
                  .collection('landlords')
                  .doc(widget.landlordUid)
                  .snapshots(),
              builder: (context, snapshot) {
                String status = "Open";
                List<dynamic> messages = [];

                if (snapshot.hasData && snapshot.data!.exists) {
                  var data = snapshot.data!.data() as Map<String, dynamic>;
                  status = data['status'] ?? "Open";
                  messages = data['messages'] ?? [];
                }

                return Column(
                  children: [
                    // --- FIXED HEADER WITH CUSTOM NAV BAR ---
                    Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        CustomTopNavBar(
                          showBack: true,
                          title: widget.apartmentName,
                          onBack: () => Navigator.pop(context),
                        ),
                        if (status == "Open")
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: IconButton(
                              icon: const Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                                size: 28,
                              ),
                              onPressed: _closeGrievance,
                              tooltip: "Mark as Resolved",
                            ),
                          ),
                      ],
                    ),

                    // --- CHAT MESSAGES AREA ---
                    Expanded(
                      child: messages.isEmpty
                          ? const Center(
                              child: Text(
                                "Start a conversation...",
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : ListView.builder(
                              reverse: true, // Show newest at bottom
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                // Reverse the list for display because of reverse: true
                                var msg = messages[messages.length - 1 - index];
                                bool isMe = msg['s'] == "t";
                                return _buildChatBubble(msg['msg'], isMe);
                              },
                            ),
                    ),

                    // --- CONDITIONAL INPUT OR BANNER ---
                    status == "Open"
                        ? _buildInputArea()
                        : _buildResolvedBanner(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.blueAccent : Colors.white10,
          borderRadius: BorderRadius.circular(15).copyWith(
            bottomRight: isMe
                ? const Radius.circular(0)
                : const Radius.circular(15),
            bottomLeft: isMe
                ? const Radius.circular(15)
                : const Radius.circular(0),
          ),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.black26,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Type a message...",
                hintStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blueAccent,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResolvedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      color: Colors.green.withOpacity(0.15),
      child: const Center(
        child: Text(
          "This grievance has been resolved.",
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
