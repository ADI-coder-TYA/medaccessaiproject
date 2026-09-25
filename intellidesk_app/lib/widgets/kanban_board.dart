import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ticket_provider.dart';
import '../models/ticket.dart';
import 'ticket_card.dart';
import 'ticket_detail_drawer.dart';
import 'glass_card.dart';

class KanbanBoard extends StatefulWidget {
  const KanbanBoard({super.key});

  @override
  State<KanbanBoard> createState() => _KanbanBoardState();
}

class _KanbanBoardState extends State<KanbanBoard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Ticket? _selectedTicket;
  String _searchQuery = '';
  String _selectedFilter = 'ALL'; // ALL, CRITICAL, HIGH, ROUTINE

  void _openTicketDrawer(Ticket ticket) {
    setState(() {
      _selectedTicket = ticket;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  List<Ticket> _filterTickets(List<Ticket> tickets) {
    if (_searchQuery.isEmpty) return tickets;
    final query = _searchQuery.toLowerCase();
    return tickets.where((t) {
      return t.studentPhone.toLowerCase().contains(query) ||
          t.rawMessage.toLowerCase().contains(query) ||
          t.id.toLowerCase().contains(query) ||
          (t.flagReason != null && t.flagReason!.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      endDrawer: _selectedTicket != null
          ? TicketDetailDrawer(ticket: _selectedTicket!)
          : null,
      body: Consumer<TicketProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.tickets.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFEE4D9F)),
            );
          }

          final criticals = _filterTickets(provider.criticalTickets);
          final highs = _filterTickets(provider.highTickets);
          final routines = _filterTickets(provider.routineTickets);

          return Column(
            children: [
              // Search & Filter Quick Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  borderRadius: 24,
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Color(0xFF1F1B2C), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: const TextStyle(fontSize: 14, color: Color(0xFF1F1B2C)),
                          decoration: InputDecoration(
                            hintText: 'Search tickets by student phone, ID, or content...',
                            hintStyle: TextStyle(color: const Color(0xFF1F1B2C).withValues(alpha: 0.4), fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _searchQuery = ''),
                        ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.tune, color: Color(0xFFEE4D9F)),
                        onSelected: (val) => setState(() => _selectedFilter = val),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'ALL', child: Text('All Severities')),
                          const PopupMenuItem(value: 'CRITICAL', child: Text('Critical Only')),
                          const PopupMenuItem(value: 'HIGH', child: Text('High Priority Only')),
                          const PopupMenuItem(value: 'ROUTINE', child: Text('Routine Only')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 800) {
                      return PageView(
                        children: [
                          if (_selectedFilter == 'ALL' || _selectedFilter == 'CRITICAL')
                            _buildColumn('Critical / Urgent', criticals, const Color(0xFFEF4444), Icons.error_outline),
                          if (_selectedFilter == 'ALL' || _selectedFilter == 'HIGH')
                            _buildColumn('High Priority', highs, const Color(0xFFF59E0B), Icons.warning_amber_outlined),
                          if (_selectedFilter == 'ALL' || _selectedFilter == 'ROUTINE')
                            _buildColumn('Routine / Pending', routines, const Color(0xFF10B981), Icons.check_circle_outline),
                        ],
                      );
                    }
                    
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedFilter == 'ALL' || _selectedFilter == 'CRITICAL')
                          Expanded(child: _buildColumn('Critical / Urgent', criticals, const Color(0xFFEF4444), Icons.error_outline)),
                        if (_selectedFilter == 'ALL' || _selectedFilter == 'HIGH')
                          Expanded(child: _buildColumn('High Priority', highs, const Color(0xFFF59E0B), Icons.warning_amber_outlined)),
                        if (_selectedFilter == 'ALL' || _selectedFilter == 'ROUTINE')
                          Expanded(child: _buildColumn('Routine / Pending', routines, const Color(0xFF10B981), Icons.check_circle_outline)),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColumn(String title, List<Ticket> tickets, Color themeColor, IconData headerIcon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F1B2C).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  themeColor.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                bottom: BorderSide(color: themeColor.withValues(alpha: 0.2), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(headerIcon, color: themeColor, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF1F1B2C),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: themeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${tickets.length}',
                    style: TextStyle(
                      color: themeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: tickets.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: themeColor.withValues(alpha: 0.12),
                                ),
                              ),
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: themeColor.withValues(alpha: 0.1),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  headerIcon,
                                  size: 40,
                                  color: themeColor.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                title.contains('Critical') ? 'Queue All Clear' : 'No Tickets',
                                style: const TextStyle(
                                  color: Color(0xFF1F1B2C),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title.contains('Critical')
                                    ? 'No high severity issues pending resolution.'
                                    : 'No tickets matching current filters.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFF1F1B2C).withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: tickets.length,
                    itemBuilder: (context, index) {
                      return TicketCard(
                        ticket: tickets[index],
                        onTapOverride: () {
                          _openTicketDrawer(tickets[index]);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

