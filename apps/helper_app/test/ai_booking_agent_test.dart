import 'package:flutter_test/flutter_test.dart';
import 'package:maidledger/core/services/ai_booking_agent_service.dart';

void main() {
  group('AIBookingAgent', () {
    late AIBookingAgent agent;

    setUp(() {
      agent = AIBookingAgent(
        geminiApiKey: '', // No API key - will use keyword engine
        translateApiKey: '',
      );
    });

    test('parseExpense detects food purchase in Chinese', () async {
      final intent = await agent.parseExpense('買咗菜 45蚊');
      
      // Keyword engine detects 'buy' intent for '買'
      expect(intent.intent, equals('buy'));
      expect(intent.amount, equals(45.0));
    });

    test('parseExpense detects supermarket purchase', () async {
      final intent = await agent.parseExpense('超市 50');
      
      // '超市' matches 'supermarket' keyword -> 'supermarket' intent
      expect(intent.intent, equals('supermarket'));
      expect(intent.amount, equals(50.0));
    });

    test('parseExpense detects wet market purchase', () async {
      final intent = await agent.parseExpense('街市買魚 80');
      
      // 'buy' detected (due to 買 keyword) before market match
      expect(intent.intent, equals('buy'));
      expect(intent.amount, equals(80.0));
    });

    test('parseExpense handles English input', () async {
      final intent = await agent.parseExpense('bought groceries 30');
      
      // 'bought' is a buy keyword
      expect(intent.intent, equals('buy'));
      expect(intent.amount, equals(30.0));
    });

    test('buildResponse generates formatted message', () {
      final intent = ExpenseIntent(
        rawText: '超市 50',
        intent: 'buy',
        category: 'food',
        amount: 50.0,
        confidence: 0.9,
      );

      final response = agent.buildResponse(intent);
      
      expect(response, contains('\$50'));
      expect(response, contains('食物'));
    });

    test('buildResponse handles low confidence', () {
      final intent = ExpenseIntent(
        rawText: 'random text',
        intent: 'unknown',
        confidence: 0.1,
        fallback: true,
      );

      final response = agent.buildResponse(intent);
      
      expect(response, contains('不太確定'));
    });
  });
}