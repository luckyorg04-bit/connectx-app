import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'services/rtc_config.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({Key? key}) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidateSubscription;
  Timer? _ringTimeoutTimer;
  Timer? _durationTimer;
  Timer? _iceDisconnectTimer;
  bool _iceCurrentlyConnected = false;
  DateTime? _connectedAt;
  Duration _elapsed = Duration.zero;
  bool _mediaConnected = false;
  bool _callEventWritten = false;
  String _callId = '';
  String _peerName = 'ConnectX user';
  String _peerUid = '';
  bool _isCaller = false;
  bool _isVideo = false;
  bool _ready = false;
  bool _connecting = false;
  bool _accepted = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = false;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  bool _leaving = false;
  String? _error;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _callRef =>
      FirebaseFirestore.instance.collection('calls').doc(_callId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final args = ModalRoute.of(context)!.settings.arguments as Map;
    _callId = args['callId'].toString();
    _peerUid = args['peerUid'].toString();
    _peerName = (args['peerName'] ?? 'ConnectX user').toString();
    _isCaller = args['isCaller'] == true;
    _isVideo = args['isVideo'] == true;
    _ready = true;
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final config = await RtcConfig.load();
      _peer = await createPeerConnection(config);
      _peer!.onIceConnectionState = (state) {
        final connected =
            state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted;
        if (connected) {
          _iceCurrentlyConnected = true;
          _iceDisconnectTimer?.cancel();
          if (_error == 'Media connection interrupted. Reconnecting…' && mounted) {
            setState(() => _error = null);
          }
          _markMediaConnected();
        } else {
          _iceCurrentlyConnected = false;
          if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
            _iceDisconnectTimer?.cancel();
            _iceDisconnectTimer = Timer(const Duration(seconds: 8), () {
              if (mounted && !_leaving && !_iceCurrentlyConnected) {
                setState(() => _error = 'Media connection interrupted. Reconnecting…');
              }
            });
          } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed && mounted && !_leaving) {
            _iceDisconnectTimer?.cancel();
            setState(() => _error = 'Media connection failed. Check network/TURN connectivity and try again.');
          }
        }
        debugPrint('ConnectX ICE connection state: $state');
      };
      _peer!.onAddStream = (stream) {
        _remoteStream = stream;
        if (!mounted) return;
        setState(() => _remoteRenderer.srcObject = stream);
      };
      _peer!.onIceCandidate = (candidate) async {
        if (candidate.candidate == null) return;
        final side = _isCaller ? 'callerCandidates' : 'calleeCandidates';
        try {
          await _callRef.collection(side).add({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'senderUid': _uid,
          });
        } catch (error) {
          debugPrint('ConnectX ICE candidate write failed: $error');
          if (mounted) setState(() => _error = 'Network candidate could not be sent. Check Firestore call permissions.');
        }
      };
      _peer!.onTrack = (event) async {
        try {
          // Some Android/WebRTC combinations deliver streamless tracks. Build a
          // remote MediaStream in that case so audio and video are still attached.
          MediaStream stream;
          if (event.streams.isNotEmpty) {
            stream = event.streams.first;
            _remoteStream = stream;
          } else {
            _remoteStream ??= await createLocalMediaStream('connectx-remote');
            stream = _remoteStream!;
            await stream.addTrack(event.track);
          }
          if (!mounted) return;
          setState(() => _remoteRenderer.srcObject = stream);
          debugPrint('ConnectX remote ${event.track.kind} track attached');
        } catch (error) {
          debugPrint('ConnectX remote track attach failed: $error');
          if (mounted) setState(() => _error = 'Remote media could not be displayed: $error');
        }
      };
      _callSubscription = _callRef.snapshots().listen(_handleCallUpdate);
      if (!_isCaller) {
        try {
          await FlutterRingtonePlayer.playRingtone(looping: true);
        } catch (error) {
          debugPrint('ConnectX incoming ringtone unavailable: $error');
        }
      }
      if (_isCaller) await _startOutgoingCall();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not initialize call: $error');
    }
  }

  void _markMediaConnected() {
    if (_mediaConnected || _leaving) return;
    _mediaConnected = true;
    _connectedAt = DateTime.now();
    _elapsed = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_connectedAt!));
    });
    _callRef.update({'connectedAt': FieldValue.serverTimestamp()}).catchError((error) {
      debugPrint('ConnectX connected timestamp write failed: $error');
    });
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _writeCallChatEvent(Map<String, dynamic> data) async {
    if (!_isCaller || _callEventWritten) return;
    _callEventWritten = true;
    try {
      final caller = (data['callerUid'] ?? _uid).toString();
      final callee = (data['calleeUid'] ?? _peerUid).toString();
      final conversationId = caller.compareTo(callee) <= 0 ? '$caller,$callee' : '$callee,$caller';
      final connected = data['connectedAt'] ?? data['acceptedAt'];
      final ended = data['endedAt'];
      DateTime? start;
      DateTime? finish;
      if (connected is Timestamp) start = connected.toDate();
      if (connected is DateTime) start = connected;
      if (ended is Timestamp) finish = ended.toDate();
      if (ended is DateTime) finish = ended;
      final durationMs = start == null ? 0 : ((finish ?? DateTime.now()).difference(start).inMilliseconds).clamp(0, 86400000);
      final typeLabel = data['type'] == 'video' ? 'Video call' : 'Voice call';
      final status = (data['status'] ?? '').toString();
      final detail = status == 'missed' ? 'Missed $typeLabel' :
        status == 'declined' ? '$typeLabel declined' :
        status == 'cancelled' ? '$typeLabel cancelled' : '$typeLabel · ${_formatDuration(Duration(milliseconds: durationMs))}';
      await FirebaseFirestore.instance.collection('messages').doc(conversationId)
        .collection('chats').doc('call_$_callId').set({
          'message': detail,
          'type': 'call',
          'durationMs': durationMs,
          'isRead': false,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'sender': _uid,
          'isEdited': false,
          'isForwarded': false,
          'reactions': <String, dynamic>{},
          'callId': _callId,
          'callType': data['type'] ?? (_isVideo ? 'video' : 'voice'),
        });
    } catch (error) {
      _callEventWritten = false;
      debugPrint('ConnectX call chat event write failed: $error');
    }
  }

  Future<void> _prepareMedia() async {
    final microphonePermission = await Permission.microphone.request();
    if (!microphonePermission.isGranted) {
      throw Exception('Microphone permission is required. Allow microphone access in Android app settings.');
    }
    if (_isVideo) {
      final cameraPermission = await Permission.camera.request();
      if (!cameraPermission.isGranted) {
        throw Exception('Camera permission is required for video calls. Allow camera access in Android app settings.');
      }
    }
    final constraints = {
      'audio': true,
      'video': _isVideo ? {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      } : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    _localRenderer.srcObject = _localStream;
    try {
      await Helper.setSpeakerphoneOn(_isVideo);
      _speakerOn = _isVideo;
    } catch (error) {
      debugPrint('ConnectX speakerphone initialization failed: $error');
    }
    for (final track in _localStream!.getTracks()) {
      await _peer!.addTrack(track, _localStream!);
    }
  }

  Future<void> _startOutgoingCall() async {
    setState(() => _connecting = true);
    try {
      await _callRef.set({
        'callerUid': _uid,
        'calleeUid': _peerUid,
        'participants': [_uid, _peerUid],
        'callerName': FirebaseAuth.instance.currentUser?.displayName ?? 'ConnectX user',
        'calleeName': _peerName,
        'type': _isVideo ? 'video' : 'voice',
        'status': 'ringing',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _prepareMedia();
      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      await _callRef.update({'offer': {'sdp': offer.sdp, 'type': offer.type}});
      _listenCandidates('calleeCandidates');
      _ringTimeoutTimer = Timer(const Duration(seconds: 45), () {
        if (!_accepted && mounted) _finishCall('missed');
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Call could not start: $error');
      try {
        await _callRef.update({'status': 'failed', 'endedAt': FieldValue.serverTimestamp()});
      } catch (updateError) {
        debugPrint('ConnectX failed-call status update failed: $updateError');
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _acceptCall() async {
    if (_connecting || _accepted) return;
    setState(() => _connecting = true);
    try {
      final snap = await _callRef.get();
      final data = snap.data();
      if (data == null || data['status'] != 'ringing' || data['calleeUid'] != _uid) {
        throw Exception('This call is no longer available.');
      }
      final offer = Map<String, dynamic>.from(data['offer'] ?? {});
      if (offer['sdp'] == null) throw Exception('The caller offer is not ready yet. Try again.');
      await _prepareMedia();
      await _peer!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
      _remoteDescriptionSet = true;
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await _callRef.update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      _listenCandidates('callerCandidates');
      await FlutterRingtonePlayer.stop();
      if (mounted) setState(() => _accepted = true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not answer call: $error');
      try {
        await _callRef.update({'status': 'declined', 'endedAt': FieldValue.serverTimestamp()});
      } catch (updateError) {
        debugPrint('ConnectX answer-failure status update failed: $updateError');
      }
      await FlutterRingtonePlayer.stop();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _handleCallUpdate(DocumentSnapshot<Map<String, dynamic>> snapshot) async {
    final data = snapshot.data();
    if (data == null) return;
    final status = (data['status'] ?? '').toString();
    if (_isCaller && !_remoteDescriptionSet && data['answer'] is Map) {
      final answer = Map<String, dynamic>.from(data['answer']);
      if (answer['sdp'] != null) {
        _ringTimeoutTimer?.cancel();
    FlutterRingtonePlayer.stop();
        await _peer?.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
        _remoteDescriptionSet = true;
        await _flushPendingRemoteCandidates();
        if (mounted) setState(() => _accepted = true);
      }
    }
    if (status == 'failed' && _error != null) return;
    if (_isCaller && (status == 'declined' || status == 'busy' || status == 'ended' || status == 'failed' || status == 'missed' || status == 'cancelled')) {
      await _writeCallChatEvent(data);
    }
    if (status == 'declined' || status == 'busy' || status == 'ended' || status == 'failed' || status == 'missed' || status == 'cancelled') {
      FlutterRingtonePlayer.stop();
      if (!_leaving && mounted && ModalRoute.of(context)?.isCurrent == true) {
        _leaving = true;
        Navigator.of(context).pop();
      }
    }
  }

  void _listenCandidates(String collection) {
    _candidateSubscription?.cancel();
    _candidateSubscription = _callRef.collection(collection).snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null || data['senderUid'] == _uid) continue;
        final candidate = data['candidate'];
        if (candidate == null) continue;
        final iceCandidate = RTCIceCandidate(
          candidate.toString(),
          data['sdpMid']?.toString(),
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteDescriptionSet) {
          _peer?.addCandidate(iceCandidate).catchError((error) {
            debugPrint('ConnectX remote ICE candidate rejected: $error');
          });
        } else {
          _pendingRemoteCandidates.add(iceCandidate);
        }
      }
    });
  }

  Future<void> _flushPendingRemoteCandidates() async {
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await _peer?.addCandidate(candidate);
      } catch (error) {
        debugPrint('ConnectX queued ICE candidate could not be added: $error');
      }
    }
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

  Future<void> _finishCall(String status) async {
    if (_leaving) return;
    _leaving = true;
    await FlutterRingtonePlayer.stop();
    _durationTimer?.cancel();
    try {
      await _callRef.update({'status': status, 'endedAt': FieldValue.serverTimestamp()});
      if (_isCaller) {
        final finalSnap = await _callRef.get();
        await _writeCallChatEvent(finalSnap.data() ?? {'status': status, 'type': _isVideo ? 'video' : 'voice'});
      }
    } catch (error) {
      debugPrint('ConnectX call status update failed ($status): $error');
    }
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }


  @override
  void dispose() {
    _ringTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _iceDisconnectTimer?.cancel();
    _callSubscription?.cancel();
    _candidateSubscription?.cancel();
    _peer?.close();
    _localStream?.dispose();
    _remoteStream?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101820),
        title: Text('${_isVideo ? 'Video' : 'Voice'} call · $_peerName'),
      ),
      body: WillPopScope(
        onWillPop: () async { await _finishCall(_isCaller && !_accepted ? 'cancelled' : 'ended'); return false; },
        child: SafeArea(child: Column(children: [
        Expanded(child: Stack(children: [
          Positioned.fill(child: _isVideo && _remoteRenderer.srcObject != null
            ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : const Center(child: Icon(Icons.person, size: 110, color: Colors.white54))),
          if (_isVideo && _localRenderer.srcObject != null)
            Positioned(right: 16, top: 16, width: 112, height: 160,
              child: ClipRRect(borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(_localRenderer, mirror: true))),
          if (_isVideo && _mediaConnected)
            Positioned(left: 16, top: 16, child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(18)),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(_formatDuration(_elapsed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            )),
          if (!_isVideo)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircleAvatar(radius: 52, child: Icon(Icons.person, size: 54)),
              const SizedBox(height: 16),
              Text(_peerName, style: const TextStyle(color: Colors.white, fontSize: 22)),
              const SizedBox(height: 8),
              Text(_mediaConnected ? _formatDuration(_elapsed) : _accepted ? 'Connecting media…' : _connecting ? 'Connecting…' : _isCaller ? 'Calling…' : 'Incoming call',
                style: const TextStyle(color: Colors.white70)),
            ])),
          if (_error != null)
            Positioned(left: 16, right: 16, bottom: 16,
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        ])),
        Padding(padding: const EdgeInsets.all(22), child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (_accepted || _isCaller)
              CircleAvatar(backgroundColor: _muted ? Colors.red : Colors.white24,
                child: IconButton(onPressed: _toggleMute, icon: Icon(_muted ? Icons.mic_off : Icons.mic, color: Colors.white))),
            if (_accepted)
              CircleAvatar(backgroundColor: _speakerOn ? Colors.white24 : Colors.red,
                child: IconButton(onPressed: _toggleSpeaker,
                  icon: Icon(_speakerOn ? Icons.volume_up : Icons.hearing, color: Colors.white))),
            if (_isVideo && (_accepted || _isCaller))
              CircleAvatar(backgroundColor: _cameraOff ? Colors.red : Colors.white24,
                child: IconButton(onPressed: _toggleCamera, icon: Icon(_cameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white))),
            if (!_isCaller && !_accepted) ...[
              CircleAvatar(backgroundColor: Colors.red, radius: 29,
                child: IconButton(onPressed: _connecting ? null : () => _finishCall('declined'),
                  icon: const Icon(Icons.call_end, color: Colors.white))),
              CircleAvatar(backgroundColor: Colors.green, radius: 29,
                child: IconButton(onPressed: _connecting ? null : _acceptCall,
                  icon: const Icon(Icons.call, color: Colors.white))),
            ],
            if (_isCaller || _accepted)
              CircleAvatar(backgroundColor: Colors.red, radius: 29,
                child: IconButton(onPressed: () => _finishCall(_isCaller && !_accepted ? 'cancelled' : 'ended'),
                  icon: const Icon(Icons.call_end, color: Colors.white))),
          ],
        )),
      ]))),
    );
  }
}
