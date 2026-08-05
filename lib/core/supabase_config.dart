import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://fkynxmfnsgtafrsbzwtu.supabase.co';
const String supabaseAnonKey = 'sb_publishable_LChWi76RMEeTPXzhnezT_w_f1OrbalK';

SupabaseClient get supabase => Supabase.instance.client;
