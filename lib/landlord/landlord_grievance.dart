import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';

class LandlordGrievancePage extends StatefulWidget {
  const LandlordGrievancePage({super.key});

  @override
  State<LandlordGrievancePage> createState() => _LandlordGrievancePageState();
}

class _LandlordGrievancePageState extends State<LandlordGrievancePage> {
  final String _landlordUid = FirebaseAuth.instance.currentUser?.uid ?? "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const AnimatedGradientBackground(), // Background from tenant.dart
          SafeArea(
            child: Column(
              children: [
                // CustomTopNavBar from main.dart
                CustomTopNavBar(
                  showBack: true,
                  title: "Tenant Grievances",
                  onBack: () => Navigator.pop(context),
                ),

                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    // CollectionGroup looks at all 'landlords' subcollections
                    // across all tenant documents.
                    stream: FirebaseFirestore.instance
                        .collectionGroup('landlords')
                        .where(
                          'participants.l',
                          isEqualTo: _landlordUid,
                        ) // NEW FIX
                        .snapshots(),
                    builder: (context, snapshot) {
                      // --- ADD THESE 3 LINES ---
                      if (snapshot.hasError) {
                        print("FIRESTORE ERROR: ${snapshot.error}");
                        return Center(
                          child: SelectableText(
                            "Error: ${snapshot.error}",
                            style: const TextStyle(color: Colors.red),
                          ),
                        );
                      }
                      // -------------------------

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text(
                            "No grievances found from your tenants.",
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          var doc = snapshot.data!.docs[index];
                          var data = doc.data() as Map<String, dynamic>;

                          // The 'parent' of the landlord doc is the 'landlords' collection.
                          // The 'parent' of that collection is the specific Tenant's document.
                          String tenantUid = doc.reference.parent.parent!.id;

                          return _buildGrievanceListTile(
                            data,
                            tenantUid,
                            doc.reference,
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

  Widget _buildGrievanceListTile(
    Map<String, dynamic> data,
    String tenantUid,
    DocumentReference docRef,
  ) {
    String status = data['status'] ?? "Open";
    bool isResolved = status == "Resolved";

    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isResolved
              ? Colors.green.withOpacity(0.2)
              : Colors.orange.withOpacity(0.2),
          child: Icon(
            isResolved ? Icons.check_circle : Icons.warning_amber_rounded,
            color: isResolved ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(
          data['apartmentName'] ?? "Property Unit",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          "Status: $status",
          style: TextStyle(
            color: isResolved ? Colors.green : Colors.orange,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LandlordChatPage(
                apartmentName: data['apartmentName'] ?? "Property",
                docRef: docRef,
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- LANDLORD CHAT PAGE ---

class LandlordChatPage extends StatefulWidget {
  final String apartmentName;
  final DocumentReference docRef;

  const LandlordChatPage({
    super.key,
    required this.apartmentName,
    required this.docRef,
  });

  @override
  State<LandlordChatPage> createState() => _LandlordChatPageState();
}

class _LandlordChatPageState extends State<LandlordChatPage> {
  final TextEditingController _messageController = TextEditingController();

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final newMessage = {
      "s": "l", // 'l' identifies Landlord in the chat bubble logic
      "msg": _messageController.text.trim(),
      "time": DateTime.now().toIso8601String(),
    };

    await widget.docRef.update({
      "messages": FieldValue.arrayUnion([newMessage]),
    });

    _messageController.clear();
  }

  void _resolveGrievance() async {
    await widget.docRef.update({"status": "Resolved"});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const AnimatedGradientBackground(),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: widget.docRef.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: CircularProgressIndicator());
                }

                var data = snapshot.data!.data() as Map<String, dynamic>;
                List<dynamic> messages = data['messages'] ?? [];
                String status = data['status'] ?? "Open";

                return Column(
                  children: [
                    // Top Bar with Resolve Button in a Stack to avoid 'actions' error
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
                                Icons.done_all,
                                color: Colors.green,
                                size: 28,
                              ),
                              onPressed: _resolveGrievance,
                              tooltip: "Mark as Resolved",
                            ),
                          ),
                      ],
                    ),

                    // Chat History
                    Expanded(
                      child: ListView.builder(
                        reverse: true, // Newest messages at bottom
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          var msg = messages[messages.length - 1 - index];
                          bool isMe = msg['s'] == "l"; // Landlord is 'l'
                          return _buildChatBubble(msg['msg'], isMe);
                        },
                      ),
                    ),

                    // Bottom Input Area
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
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isMe ? Colors.orange.shade800 : Colors.white10,
          borderRadius: BorderRadius.circular(15).copyWith(
            bottomRight: isMe
                ? const Radius.circular(0)
                : const Radius.circular(15),
            bottomLeft: isMe
                ? const Radius.circular(15)
                : const Radius.circular(0),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(color: Colors.black26),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Reply to tenant...",
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
            backgroundColor: Colors.orange.shade800,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.15)),
      child: const Center(
        child: Text(
          "Issue Resolved - Chat Closed",
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
