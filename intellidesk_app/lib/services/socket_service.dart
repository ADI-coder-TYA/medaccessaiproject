import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/ticket.dart';
import '../config/api_config.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;
  String get url => ApiConfig.socketUrl;
  
  Function(Ticket)? onTicketCreated;
  Function(Ticket)? onTicketUpdated;
  Function(Map<String, dynamic>)? _onClaimUpdatedCallback;
  Function(Map<String, dynamic>)? _onClaimDisbursedCallback;
  Function(Map<String, dynamic>)? _onEmergencyAlertCallback;
  Function(Map<String, dynamic>)? _onChatMessageCallback;
  Function(bool)? onConnectionStateChanged;

  void onClaimUpdated(Function(Map<String, dynamic>) callback) {
    _onClaimUpdatedCallback = callback;
  }

  void onClaimDisbursed(Function(Map<String, dynamic>) callback) {
    _onClaimDisbursedCallback = callback;
  }

  void onEmergencyAlert(Function(Map<String, dynamic>) callback) {
    _onEmergencyAlertCallback = callback;
  }

  void onChatMessage(Function(Map<String, dynamic>) callback) {
    _onChatMessageCallback = callback;
  }

  void connect({String institutionId = 'default'}) {
    if (_socket != null && _socket!.connected) {
      if (onConnectionStateChanged != null) {
        onConnectionStateChanged!(true);
      }
      return;
    }

    _socket?.dispose();

    _socket = io.io(url, io.OptionBuilder()
      .setTransports(['websocket'])
      .enableAutoConnect()
      .enableReconnection()
      .setReconnectionDelay(1000)
      .setReconnectionAttempts(999)
      .build()
    );

    _socket!.onConnect((_) {
      debugPrint('🔌 [SocketService] Connected to $url');
      if (ApiConfig.userRole == 'ADMIN' || ApiConfig.userRole == 'CLINICAL_ADMIN') {
        _socket?.emit('join_admin', {'institutionId': institutionId});
      }
      _socket?.emit('join_institution', institutionId);
      if (onConnectionStateChanged != null) {
        onConnectionStateChanged!(true);
      }
    });

    _socket!.onReconnect((_) {
      debugPrint('🔌 [SocketService] Reconnected to $url');
      if (onConnectionStateChanged != null) {
        onConnectionStateChanged!(true);
      }
    });

    _socket!.onConnectError((err) {
      debugPrint('⚠️ [SocketService] connect_error: $err');
      if (onConnectionStateChanged != null) {
        onConnectionStateChanged!(false);
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('🔌 [SocketService] Disconnected from $url');
      if (onConnectionStateChanged != null) {
        onConnectionStateChanged!(false);
      }
    });

    _socket!.on('claim:updated', (data) {
      if (data != null && _onClaimUpdatedCallback != null) {
        _onClaimUpdatedCallback!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('claim:disbursed', (data) {
      if (data != null && _onClaimDisbursedCallback != null) {
        _onClaimDisbursedCallback!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('emergency:alert', (data) {
      if (data != null && _onEmergencyAlertCallback != null) {
        _onEmergencyAlertCallback!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('chat:new_message', (data) {
      if (data != null && _onChatMessageCallback != null) {
        _onChatMessageCallback!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('ticket:created', (data) {
      if (data != null) {
        try {
          final ticket = Ticket.fromJson(Map<String, dynamic>.from(data));
          if (onTicketCreated != null) {
            onTicketCreated!(ticket);
          }
        } catch (e) {
          debugPrint('Error parsing ticket:created data: $e');
        }
      }
    });

    _socket!.on('ticket:updated', (data) {
      if (data != null) {
        try {
          final ticket = Ticket.fromJson(Map<String, dynamic>.from(data));
          if (onTicketUpdated != null) {
            onTicketUpdated!(ticket);
          }
        } catch (e) {
          debugPrint('Error parsing ticket:updated data: $e');
        }
      }
    });

    _socket!.connect();
  }

  void joinClaim(String claimId) {
    _socket?.emit('join_claim', claimId);
    _socket?.emit('join_ticket', claimId);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
