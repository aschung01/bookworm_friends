import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'YOUR_SUPABASE_URL';
const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

SupabaseClient get supabase => Supabase.instance.client;
