import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

@immutable
class DagNode {
  final String txId;
  final String data;
  final int timestamp;
  final List<String> parents;
  final int nonce;
  final int depth;

  const DagNode({
    required this.txId,
    required this.data,
    required this.timestamp,
    required this.parents,
    required this.nonce,
    required this.depth,
  });
}

class MiningTask {
  final String data;
  final int timestamp;
  final List<String> parents;
  final int difficulty;
  MiningTask(this.data, this.timestamp, this.parents, this.difficulty);
}

class MiningResult {
  final String txId;
  final int nonce;
  MiningResult(this.txId, this.nonce);
}

MiningResult _mineNode(MiningTask task) {
  int nonce = 0;
  String hash = '';
  final String prefix = List.filled(task.difficulty, '0').join();
  do {
    nonce++;
    final content =
        "${task.data}|${task.timestamp}|${task.parents.join(',')}|$nonce";
    hash = sha256.convert(utf8.encode(content)).toString();
  } while (!hash.startsWith(prefix));
  return MiningResult(hash, nonce);
}

class DagLedger extends ChangeNotifier {
  static final DagLedger _instance = DagLedger._internal();
  static DagLedger get instance => _instance;

  final Map<String, DagNode> _dag = {};
  final int difficulty = 2;
  bool isSynced = false;

  DagLedger._internal() {
    _createGenesis();
    _syncFromFirestore();
  }

  List<DagNode> get allNodes => List.unmodifiable(_dag.values);

  void _createGenesis() {
    const genesisId =
        "0000000000000000000000000000000000000000000000000000000000000000";
    _dag[genesisId] = const DagNode(
      txId: genesisId,
      data: "Genesis Block",
      timestamp: 0,
      parents: [],
      nonce: 0,
      depth: 0,
    );
  }

  Future<void> _syncFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('dag_nodes')
          .orderBy('timestamp')
          .get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final node = DagNode(
          txId: data['txId'],
          data: data['data'],
          timestamp: data['timestamp'],
          parents: List<String>.from(data['parents'] ?? []),
          nonce: data['nonce'],
          depth: data['depth'],
        );
        _dag[node.txId] = node;
      }
      isSynced = true;
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to sync DAG from Firestore: $e");
    }
  }

  List<String> getTips() {
    final Set<String> parentIds = {};
    for (final node in _dag.values) {
      parentIds.addAll(node.parents);
    }
    final tips = _dag.keys.where((id) => !parentIds.contains(id)).toList();
    if (tips.isEmpty) return [_dag.keys.first];
    tips.shuffle();
    return tips.take(2).toList();
  }

  // Returns the txId (Hash) of the new node
  Future<String> addTransaction(String data) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final parents = getTips();

    int maxParentDepth = 0;
    for (final p in parents) {
      if (_dag[p] != null && _dag[p]!.depth > maxParentDepth) {
        maxParentDepth = _dag[p]!.depth;
      }
    }
    final depth = maxParentDepth + 1;

    final task = MiningTask(data, timestamp, parents, difficulty);
    final result = await compute(_mineNode, task);

    final newNode = DagNode(
      txId: result.txId,
      data: data,
      timestamp: timestamp,
      parents: parents,
      nonce: result.nonce,
      depth: depth,
    );

    // Save to RAM
    _dag[result.txId] = newNode;
    notifyListeners();

    // Save permanently to Firestore
    try {
      await FirebaseFirestore.instance
          .collection('dag_nodes')
          .doc(result.txId)
          .set({
            'txId': result.txId,
            'data': data,
            'timestamp': timestamp,
            'parents': parents,
            'nonce': result.nonce,
            'depth': depth,
          });
    } catch (e) {
      debugPrint("Failed to save to dag_nodes: $e");
    }

    return result.txId;
  }
}
