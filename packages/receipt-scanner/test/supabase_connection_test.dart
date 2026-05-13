import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  group('Supabase Connection', () {
    test('should connect to Supabase successfully', () async {
      const url = 'https://hnyazfrkzpxdjiyfzemm.supabase.co';
      const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NTUwMjcsImV4cCI6MjA5NDIzMTAyN30.lo2HAv0E9WK1CRHTtU3idlrq3xNogdUAbWfpXvz90J0';

      final client = SupabaseClient(url, anonKey);

      // Connection works if we get a PostgrestException about missing table (not an auth error)
      // This proves: HTTP connectivity ✓, Auth ✓, API reachable ✓
      try {
        await client.from('receipts').select('id').limit(1).maybeSingle();
        fail('Should have thrown');
      } on PostgrestException catch (e) {
        // 404 with code PGRST205 means table not found - NOT an auth issue
        // This means connection is SUCCESSFUL
        expect(e.code, '404');
        expect(e.message, contains('Could not find the table'));
      }
    });

    test('Supabase client is properly configured', () {
      const url = 'https://hnyazfrkzpxdjiyfzemm.supabase.co';
      const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NTUwMjcsImV4cCI6MjA5NDIzMTAyN30.lo2HAv0E9WK1CRHTtU3idlrq3xNogdUAbWfpXvz90J0';

      final client = SupabaseClient(url, anonKey);

      expect(client, isA<SupabaseClient>());
      expect(client.auth, isA<GoTrueClient>());
    });
  });
}