import 'package:flutter/material.dart';
import '../models/ticket.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class TicketProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();

  List<Ticket> _tickets = [];
  bool _isLoading = false;
  bool _isConnected = false;

  List<Ticket> get tickets => _tickets;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;

  List<Ticket> get criticalTickets => 
      _tickets.where((t) => t.urgencyLevel == 'Urgent').toList();
      
  List<Ticket> get highTickets => 
      _tickets.where((t) => t.urgencyLevel == 'High').toList();
      
  List<Ticket> get routineTickets => 
      _tickets.where((t) => t.urgencyLevel == 'Routine').toList();

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    _socketService.onConnectionStateChanged = (connected) {
      _isConnected = connected;
      notifyListeners();
    };

    _socketService.onTicketCreated = (ticket) {
      final index = _tickets.indexWhere((t) => t.id == ticket.id);
      if (index == -1) {
        _tickets.add(ticket);
        notifyListeners();
      }
    };

    _socketService.onTicketUpdated = (updatedTicket) {
      final index = _tickets.indexWhere((t) => t.id == updatedTicket.id);
      if (index != -1) {
        _tickets[index] = updatedTicket;
      } else {
        _tickets.add(updatedTicket);
      }
      notifyListeners();
    };

    _socketService.connect();

    if (ApiConfig.userRole == 'ADMIN' || ApiConfig.userRole == 'CLINICAL_ADMIN') {
      try {
        _tickets = await _apiService.fetchTickets();
      } catch (e) {
        debugPrint('Error fetching initial tickets: $e');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>> approveTicket(
    String id, {
    double? amount,
    String? payoutMethod,
    String? studentName,
    String? studentVpa,
    String? accountNumber,
    String? ifscCode,
  }) async {
    try {
      final res = await _apiService.approveTicket(
        id,
        amount: amount,
        payoutMethod: payoutMethod,
        studentName: studentName,
        studentVpa: studentVpa,
        accountNumber: accountNumber,
        ifscCode: ifscCode,
      );
      await _refreshTicket(id);
      return res;
    } catch (e) {
      debugPrint('Error approving ticket: $e');
      rethrow;
    }
  }

  Future<void> denyTicket(String id, {String? notes}) async {
    try {
      await _apiService.denyTicket(id, notes: notes);
      await _refreshTicket(id);
    } catch (e) {
      debugPrint('Error denying ticket: $e');
      rethrow;
    }
  }

  Future<void> _refreshTicket(String id) async {
    try {
      final updatedTicket = await _apiService.fetchTicketById(id);
      final index = _tickets.indexWhere((t) => t.id == id);
      if (index != -1) {
        _tickets[index] = updatedTicket;
        notifyListeners();
      } else {
        _tickets.add(updatedTicket);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error refreshing ticket: $e');
    }
  }
}
