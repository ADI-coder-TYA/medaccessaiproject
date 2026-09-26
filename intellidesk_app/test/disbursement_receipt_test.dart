import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellidesk_app/models/ticket.dart';
import 'package:intellidesk_app/providers/ticket_provider.dart';
import 'package:intellidesk_app/widgets/approval_desk_dialog.dart';
import 'package:intellidesk_app/widgets/ticket_detail_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Ticket createTestTicket({
    String id = 'TICK-DISBURSE-001',
    String status = 'Approved',
    double? recommendedGrantAmount = 3500.0,
    double calculatedAmount = 4000.0,
    String? payoutReference = 'POUT-RAZOR-998811',
    String? payoutMethod = 'RAZORPAY_UPI',
    String? voucherCode,
    String? fundSourceName = 'Emergency Health Copay Relief Reserve',
    String currency = 'INR',
    String studentPhone = '+91 9876543210',
  }) {
    return Ticket(
      id: id,
      studentPhone: studentPhone,
      rawMessage: 'Need urgent pharmacy copay assistance for asthma inhaler and antibiotics.',
      parsedCategory: 'Prescription & Pharmacy Copay',
      urgencyLevel: 'Critical',
      status: status,
      calculatedAmount: calculatedAmount,
      recommendedGrantAmount: recommendedGrantAmount,
      payoutReference: payoutReference,
      payoutMethod: payoutMethod,
      voucherCode: voucherCode,
      fundSourceName: fundSourceName,
      currency: currency,
      createdAt: DateTime.now(),
    );
  }

  Widget createTestApp(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TicketProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('Live Disbursement Receipt & ApprovalDeskDialog Tests', () {
    testWidgets('Renders Live Disbursement Receipt directly for Approved Ticket', (tester) async {
      final ticket = createTestTicket();

      await tester.pumpWidget(
        createTestApp(
          ApprovalDeskDialog(
            ticket: ticket,
            initialShowReceipt: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and titles
      expect(find.text('Live Disbursement Receipt'), findsOneWidget);
      expect(
        find.text('Official institutional grant disbursement record on live ledger.'),
        findsOneWidget,
      );

      // Check amount, rail, ref
      expect(find.text('Disbursed Amount'), findsOneWidget);
      expect(find.text('Disbursement Rail'), findsOneWidget);
      expect(find.text('Razorpay UPI'), findsOneWidget);
      expect(find.text('Transaction Reference'), findsOneWidget);
      expect(find.text('POUT-RAZOR-998811'), findsOneWidget);
      expect(find.text('Fund Deducted'), findsOneWidget);
      expect(find.text('Emergency Health Copay Relief Reserve'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsWidgets);

      // Check close button exists and works
      final closeButton = find.text('Close & Return to Dashboard');
      expect(closeButton, findsOneWidget);
    });

    testWidgets('Edge Case: Handles Campus Digital Voucher with Voucher Code display', (tester) async {
      final ticket = createTestTicket(
        payoutMethod: 'CAMPUS_VOUCHER',
        voucherCode: 'VCH-PHARM-2026-X88',
        payoutReference: 'POUT-VOUCHER-01',
      );

      await tester.pumpWidget(
        createTestApp(
          ApprovalDeskDialog(
            ticket: ticket,
            initialShowReceipt: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Campus Digital Voucher'), findsOneWidget);
      expect(find.text('Voucher Code'), findsOneWidget);
      expect(find.text('VCH-PHARM-2026-X88'), findsOneWidget);
    });

    testWidgets('Edge Case: Handles USD Currency and ACH Bank Rail', (tester) async {
      final ticket = createTestTicket(
        currency: 'USD',
        payoutMethod: 'STRIPE_ACH',
        recommendedGrantAmount: 150.0,
        payoutReference: 'ach_live_test_7788',
      );

      await tester.pumpWidget(
        createTestApp(
          ApprovalDeskDialog(
            ticket: ticket,
            initialShowReceipt: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Direct Bank Transfer (ACH / SEPA)'), findsOneWidget);
      expect(find.text('ach_live_test_7788'), findsOneWidget);
      expect(find.textContaining('\$'), findsWidgets);
    });

    testWidgets('Edge Case: Handles null payoutReference and null recommendedGrantAmount gracefully', (tester) async {
      final ticket = createTestTicket(
        payoutReference: null,
        recommendedGrantAmount: null,
        calculatedAmount: 2200.0,
      );

      await tester.pumpWidget(
        createTestApp(
          ApprovalDeskDialog(
            ticket: ticket,
            initialShowReceipt: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live Disbursement Receipt'), findsOneWidget);
      expect(find.text('POUT-CONFIRMED-${ticket.id}'), findsOneWidget);
      expect(find.textContaining('2,200'), findsWidgets);
    });

    testWidgets('Edge Case: Handles zero amounts without crash', (tester) async {
      final ticket = createTestTicket(
        recommendedGrantAmount: 0.0,
        calculatedAmount: 0.0,
      );

      await tester.pumpWidget(
        createTestApp(
          ApprovalDeskDialog(
            ticket: ticket,
            initialShowReceipt: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live Disbursement Receipt'), findsOneWidget);
      expect(find.textContaining('0.00'), findsWidgets);
    });

    testWidgets('New / Under Review ticket opens in Disbursement Input Desk mode (not receipt)', (tester) async {
      final ticket = createTestTicket(
        status: 'New',
        payoutReference: null,
      );

      await tester.pumpWidget(
        createTestApp(
          ApprovalDeskDialog(
            ticket: ticket,
            initialShowReceipt: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Disbursement Desk'), findsOneWidget);
      expect(find.text('Disburse via Razorpay UPI'), findsOneWidget);
      expect(find.text('Live Disbursement Receipt'), findsNothing);
    });

    testWidgets('Narrow viewport does not trigger RenderFlex pixel overflow in receipt view', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final ticket = createTestTicket(
        payoutReference: 'VERY_LONG_TRANSACTION_REFERENCE_HASH_991827461982736192847192847',
        payoutMethod: 'STRIPE_ACH',
        fundSourceName: 'Institutional Extraordinary Hardship and Trauma Copay Relief Pool',
      );

      await tester.pumpWidget(
        createTestApp(
          ApprovalDeskDialog(
            ticket: ticket,
            initialShowReceipt: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Live Disbursement Receipt'), findsOneWidget);
    });
  });

  group('TicketDetailDrawer Disbursement Actions & Pixel Overflow Prevention', () {
    testWidgets('Approved ticket displays Copay Relief Disbursed and View Live Disbursement Receipt button', (tester) async {
      final ticket = createTestTicket(
        status: 'Approved',
        recommendedGrantAmount: 3500.0,
      );

      await tester.pumpWidget(
        createTestApp(
          TicketDetailDrawer(ticket: ticket),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Copay Relief Disbursed:'), findsOneWidget);
      expect(find.text('View Live Disbursement Receipt'), findsOneWidget);
      expect(find.text('Confirm AI Decision & Open Payment Desk'), findsNothing);
    });

    testWidgets('Tapping View Live Disbursement Receipt button pops drawer and triggers dialog in receipt mode', (tester) async {
      final ticket = createTestTicket(
        status: 'Approved',
        recommendedGrantAmount: 3500.0,
      );

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (ctx) => Scaffold(
              endDrawer: TicketDetailDrawer(ticket: ticket),
              body: Builder(
                builder: (scaffoldCtx) => ElevatedButton(
                  onPressed: () => Scaffold.of(scaffoldCtx).openEndDrawer(),
                  child: const Text('Open Drawer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open drawer
      await tester.tap(find.text('Open Drawer'));
      await tester.pumpAndSettle();

      // Verify button is in drawer
      final receiptBtn = find.text('View Live Disbursement Receipt');
      expect(receiptBtn, findsOneWidget);

      // Tap receipt button
      await tester.tap(receiptBtn);
      await tester.pumpAndSettle();

      // Verify dialog opened directly in Live Disbursement Receipt view!
      expect(find.text('Live Disbursement Receipt'), findsOneWidget);
      expect(find.text('POUT-RAZOR-998811'), findsOneWidget);
    });

    testWidgets('Narrow drawer viewport renders without RenderFlex pixel overflow', (tester) async {
      tester.view.physicalSize = const Size(300, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final ticket = createTestTicket(
        status: 'Approved',
        recommendedGrantAmount: 250000.0,
      );

      await tester.pumpWidget(
        createTestApp(
          SizedBox(
            width: 300,
            child: TicketDetailDrawer(ticket: ticket),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('View Live Disbursement Receipt'), findsOneWidget);
    });
  });
}
