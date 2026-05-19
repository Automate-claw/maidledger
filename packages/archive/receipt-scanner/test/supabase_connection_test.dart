import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  group('Supabase Connection', () {
    test('Supabase client is properly configured', () {
      const url = 'https://hnyazfrkzpxdjiyfzemm.supabase.co';
      const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NTUwMjcsImV4cCI6MjA5NDIzMTAyN30.lo2HAv0E9WK1CRHTtU3idlrq3xNogdUAbWfpXvz90J0';

      final client = SupabaseClient(url, anonKey);

      expect(client, isA<SupabaseClient>());
      expect(client.auth, isA<GoTrueClient>());
    });
  });
}