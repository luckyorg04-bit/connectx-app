import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/rtc_config.dart';

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({Key? key}) : super(key: key);

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _pairSubscriptions = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _candidateSubscriptions = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Set<String> _remoteDescriptionReady = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  MediaStream? _localStream;
  String _callId = '';
  String _groupId = '';
  String _groupName = 'Group';
  String _callType = 'voice';
  bool _initialized = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  final Set<String> _creatingPeers = <String>{};
  bool _leaving = false;
  String? _error;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _callRef =>
      FirebaseFirestore.instance.collection('groupCalls').doc(_callId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final args = ModalRoute.of(context)!.settings.arguments as Map;
    _callId = args['callId'].toString();
    _groupId = args['groupId'].toString();
    _groupName = (args['groupName'] ?? 'Group').toString();
    _callType = (args['callType'] ?? 'voice').toString();
    _initialized = true;
    _initialize(args['isCreator'] == true);
  }

  Future<void> _initialize(bool isCreator) async {
    try {
      await _localRenderer.initialize();
      final group = await FirebaseFirestore.instance.collection('groupChats').doc(_groupId).get();
      if (!group.exists || !List<String>.from(group.data()?['memberUids'] ?? []).contains(_uid)) {
        throw Exception('Only group members can join this call.');
      }
      final call = await _callRef.get();
      if (!call.exists) throw Exception('This group call is no longer available.');
      final callData = call.data()!;
      if (callData['status'] != 'active') throw Exception('This group call has ended.');
      if (isCreator && callData['createdBy'] != _uid) {
        throw Exception('Only the call creator can initialize this call as host.');
      }
      final active = List<String>.from(callData['activeUids'] ?? []);
      if (!isCreator && !active.contains(_uid) && active.length >= 8) {
        throw Exception('This group call has reached its 8 participant limit.');
      }
      await _prepareMedia();
      if (!isCreator) {
        await _callRef.update({
          'activeUids': FieldValue.arrayUnion([_uid]),
          'participants': FieldValue.arrayUnion([_uid]),
        });
      }
      _callSubscription = _callRef.snapshots().listen((snapshot) {
        final data = snapshot.data();
        if (data == null || data['status'] != 'active') {
          if (mounted && !_leaving) Navigator.of(context).maybePop();
          return;
        }
        final active = List<String>.from(data['activeUids'] ?? []);
        _syncPeers(active);
      });
    } catch (error) {
      if (isCreator) {
        try {
          await _callRef.update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
        } catch (_) {}
      }
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _prepareMedia() async {
    final microphone = await Permission.microphone.request();
    if (!microphone.isGranted) {
      throw Exception('Microphone permission is required for group calls.');
    }
    if (_callType == 'video') {
      final camera = await Permission.camera.request();
      if (!camera.isGranted) {
        throw Exception('Camera permission is required for group video calls.');
      }
    }
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': _callType == 'video'
        ? {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}}
        : false,
    });
    _localRenderer.srcObject = _localStream;
    try {
      await Helper.setSpeakerphoneOn(true);
      _speakerOn = true;
    } catch (error) {
      debugPrint('ConnectX group call speaker initialization failed: $error');
    }
    if (mounted) setState(() {});
  }

  String _pairId(String otherUid) {
    final pair = [_uid, otherUid]..sort();
    return '${pair[0]}_${pair[1]}';
  }

  Future<void> _syncPeers(List<String> activeUids) async {
    for (final peerUid in activeUids.where((id) => id != _uid)) {
      if (!_peers.containsKey(peerUid)) await _createPeer(peerUid);
    }
    final departed = _peers.keys.where((id) => !activeUids.contains(id)).toList();
    for (final id in departed) {
      await _closePeer(id);
    }
  }

  Future<void> _createPeer(String peerUid) async {
    if (_peers.containsKey(peerUid) || _creatingPeers.contains(peerUid) || _localStream == null) return;
    _creatingPeers.add(peerUid);
    try {
    final pairId = _pairId(peerUid);
    final pairRef = _callRef.collection('pairs').doc(pairId);
    final isOfferer = _uid.compareTo(peerUid) < 0;
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final peer = await createPeerConnection(await RtcConfig.load());
    _peers[peerUid] = peer;
    _remoteRenderers[peerUid] = renderer;
    for (final track in _localStream!.getTracks()) {
      await peer.addTrack(track, _localStream!);
    }
    peer.onTrack = (event) async {
      try {
        event.track.enabled = true;
        MediaStream stream;
        if (event.streams.isNotEmpty) {
          stream = event.streams.first;
        } else {
          final existing = renderer.srcObject;
          stream = existing ?? await createLocalMediaStream('connectx-group-$peerUid');
          if (existing == null) renderer.srcObject = stream;
          await stream.addTrack(event.track);
        }
        renderer.srcObject = stream;
        if (mounted) setState(() {});
      } catch (error) {
        debugPrint('ConnectX group remote track attach failed: $error');
        if (mounted) setState(() => _error = 'Could not attach a participant media track.');
      }
    };
    peer.onIceCandidate = (candidate) async {
      if (candidate.candidate == null) return;
      try {
        await pairRef.collection('candidates').add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'senderUid': _uid,
        });
      } catch (_) {}
    };
    _pairSubscriptions[peerUid] = pairRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;
      try {
        if (isOfferer && data['answer'] is Map && !_remoteDescriptionReady.contains(peerUid)) {
          final answer = Map<String, dynamic>.from(data['answer']);
          if (answer['sdp'] != null) {
            await peer.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
            _remoteDescriptionReady.add(peerUid);
            await _flushCandidates(peerUid, peer);
          }
        } else if (!isOfferer && data['offer'] is Map && !_remoteDescriptionReady.contains(peerUid)) {
          final offer = Map<String, dynamic>.from(data['offer']);
          if (offer['sdp'] != null) {
            await peer.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
            _remoteDescriptionReady.add(peerUid);
            await _flushCandidates(peerUid, peer);
            final answer = await peer.createAnswer();
            await peer.setLocalDescription(answer);
            await pairRef.set({
              'offererUid': peerUid,
              'answererUid': _uid,
              'answer': {'sdp': answer.sdp, 'type': answer.type},
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      } catch (error) {
        if (mounted) setState(() => _error = 'Call connection error: $error');
      }
    });
    _candidateSubscriptions[peerUid] = pairRef.collection('candidates').snapshots().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null || data['senderUid'] == _uid || data['candidate'] == null) continue;
        final candidate = RTCIceCandidate(
          data['candidate'].toString(), data['sdpMid']?.toString(),
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteDescriptionReady.contains(peerUid)) {
          try { await peer.addCandidate(candidate); } catch (_) {}
        } else {
          (_pendingCandidates[peerUid] ??= []).add(candidate);
        }
      }
    });
    if (isOfferer) {
      final offer = await peer.createOffer();
      await peer.setLocalDescription(offer);
      await pairRef.set({
        'offererUid': _uid,
        'answererUid': peerUid,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    } finally {
      _creatingPeers.remove(peerUid);
    }
  }

  Future<void> _flushCandidates(String peerUid, RTCPeerConnection peer) async {
    final queued = _pendingCandidates.remove(peerUid) ?? [];
    for (final candidate in queued) {
      try { await peer.addCandidate(candidate); } catch (_) {}
    }
  }

  Future<void> _closePeer(String peerUid) async {
    await _pairSubscriptions.remove(peerUid)?.cancel();
    await _candidateSubscriptions.remove(peerUid)?.cancel();
    await _peers.remove(peerUid)?.close();
    final renderer = _remoteRenderers.remove(peerUid);
    await renderer?.dispose();
    _pendingCandidates.remove(peerUid);
    _remoteDescriptionReady.remove(peerUid);
    _creatingPeers.remove(peerUid);
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    _muted = !_muted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    _cameraOff = !_cameraOff;
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_cameraOff;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
      _speakerOn = next;
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not change audio output: $error');
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final snap = await _callRef.get();
      final data = snap.data();
      if (data != null) {
        final group = await FirebaseFirestore.instance.collection('groupChats').doc(_groupId).get();
        final admins = List<String>.from(group.data()?['adminUids'] ?? [group.data()?['createdBy']]);
        if (data['createdBy'] == _uid || admins.contains(_uid)) {
          await _callRef.update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
        } else {
          await _callRef.update({'activeUids': FieldValue.arrayRemove([_uid])});
        }
      }
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    for (final sub in _pairSubscriptions.values) { sub.cancel(); }
    for (final sub in _candidateSubscriptions.values) { sub.cancel(); }
    for (final peer in _peers.values) { peer.close(); }
    for (final renderer in _remoteRenderers.values) { renderer.dispose(); }
    _localStream?.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      Container(
        decoration: BoxDecoration(color: const Color(0xFF26343C), borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (_callType == 'video' && _localRenderer.srcObject != null && !_cameraOff)
            RTCVideoView(_localRenderer, mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            const Center(child: Icon(Icons.person, color: Colors.white70, size: 58)),
          const Positioned(left: 10, bottom: 8, child: Text('You', style: TextStyle(color: Colors.white))),
        ]),
      ),
      ..._remoteRenderers.entries.map((entry) => Container(
        decoration: BoxDecoration(color: const Color(0xFF26343C), borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (_callType == 'video' && entry.value.srcObject != null)
            RTCVideoView(entry.value, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            const Center(child: Icon(Icons.person, color: Colors.white70, size: 58)),
          Positioned(left: 10, bottom: 8, child: Text('Participant ${entry.key.substring(0, entry.key.length > 6 ? 6 : entry.key.length)}',
            style: const TextStyle(color: Colors.white))),
        ]),
      )),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101820),
        title: Text('${_callType == 'video' ? 'Video' : 'Voice'} group call · $_groupName'),
      ),
      body: WillPopScope(
        onWillPop: () async { await _leave(); return false; },
        child: SafeArea(child: Column(children: [
          if (_error != null)
            Padding(padding: const EdgeInsets.all(10), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          Expanded(child: GridView.count(
            padding: const EdgeInsets.all(12),
            crossAxisCount: tiles.length <= 2 ? 1 : 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: tiles,
          )),
          Padding(padding: const EdgeInsets.all(22), child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CircleAvatar(backgroundColor: _muted ? Colors.red : Colors.white24,
                child: IconButton(onPressed: _toggleMute,
                  icon: Icon(_muted ? Icons.mic_off : Icons.mic, color: Colors.white))),
              CircleAvatar(backgroundColor: _speakerOn ? Colors.white24 : Colors.red,
                child: IconButton(onPressed: _toggleSpeaker,
                  icon: Icon(_speakerOn ? Icons.volume_up : Icons.hearing, color: Colors.white))),
              if (_callType == 'video')
                CircleAvatar(backgroundColor: _cameraOff ? Colors.red : Colors.white24,
                  child: IconButton(onPressed: _toggleCamera,
                    icon: Icon(_cameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white))),
              CircleAvatar(backgroundColor: Colors.red, radius: 29,
                child: IconButton(onPressed: _leave,
                  icon: const Icon(Icons.call_end, color: Colors.white))),
            ],
          )),
        ])),
      ),
    );
  }
}
