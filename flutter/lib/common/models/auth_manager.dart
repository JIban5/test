import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class AuthManager {
  static final AuthManager _instance = AuthManager._internal();
  factory AuthManager() => _instance;
  AuthManager._internal();

  // 服务器地址 - 修改为你的实际服务器地址
  static const String API_BASE_URL = 'http://192.168.1.100:8080/api';
  
  String? _token;
  String? _username;
  String? _role;
  List<dynamic> _myDevices = [];

  // 检查是否已登录
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _username = prefs.getString('username');
    _role = prefs.getString('role');
    
    if (_token == null) return false;
    
    // 验证 token 是否有效
    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/verify'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Token 验证失败: $e');
      return false;
    }
  }

  // 用户登录
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      // 密码加密
      final hashedPassword = sha256.convert(utf8.encode(password)).toString();
      
      final response = await http.post(
        Uri.parse('$API_BASE_URL/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': hashedPassword,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        _username = data['username'];
        _role = data['role'];
        
        // 保存到本地
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await prefs.setString('username', _username!);
        await prefs.setString('role', _role!);
        
        return {'success': true, 'message': '登录成功'};
      } else {
        final error = jsonDecode(response.body);
        return {'success': false, 'message': error['error'] ?? '登录失败'};
      }
    } catch (e) {
      return {'success': false, 'message': '网络错误: $e'};
    }
  }

  // 退出登录
  Future<void> logout() async {
    _token = null;
    _username = null;
    _role = null;
    _myDevices = [];
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('username');
    await prefs.remove('role');
  }

  // 获取当前用户的设备列表
  Future<List<dynamic>> getMyDevices({bool forceRefresh = false}) async {
    if (!forceRefresh && _myDevices.isNotEmpty) {
      return _myDevices;
    }
    
    if (_token == null) {
      throw Exception('未登录');
    }

    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/devices'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _myDevices = data['devices'] ?? [];
        return _myDevices;
      } else {
        throw Exception('获取设备列表失败');
      }
    } catch (e) {
      print('获取设备列表错误: $e');
      return [];
    }
  }

  // 检查是否有权限访问某个设备
  bool canAccessDevice(String deviceId) {
    // 管理员可以访问所有设备
    if (_role == 'admin') return true;
    
    // 检查设备是否在用户的设备列表中
    return _myDevices.any((device) => device['device_id'] == deviceId);
  }

  // 获取当前用户信息
  Map<String, String?> getCurrentUser() {
    return {
      'username': _username,
      'role': _role,
    };
  }

  // 是否为管理员
  bool isAdmin() {
    return _role == 'admin';
  }
}
