// 系统托盘和热键管理模块
#![cfg(target_os = "windows")]

use hbb_common::log;
use std::sync::{Arc, Mutex};

#[cfg(target_os = "windows")]
use global_hotkey::{GlobalHotKeyManager, hotkey::{HotKey, Code, Modifiers}};

lazy_static::lazy_static! {
    static ref HOTKEY_MANAGER: Arc<Mutex<Option<GlobalHotKeyManager>>> = Arc::new(Mutex::new(None));
    static ref WINDOW_VISIBLE: Arc<Mutex<bool>> = Arc::new(Mutex::new(true));
}

/// 初始化全局热键 Ctrl+Alt+J
pub fn init_global_hotkey() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "windows")]
    {
        let manager = GlobalHotKeyManager::new()?;
        
        // 注册 Ctrl+Alt+J
        let hotkey = HotKey::new(
            Some(Modifiers::CONTROL | Modifiers::ALT),
            Code::KeyJ,
        );
        
        manager.register(hotkey)?;
        
        *HOTKEY_MANAGER.lock().unwrap() = Some(manager);
        
        log::info!("全局热键 Ctrl+Alt+J 已注册");
        Ok(())
    }
    
    #[cfg(not(target_os = "windows"))]
    {
        log::warn!("当前系统不支持全局热键");
        Ok(())
    }
}

/// 切换窗口显示/隐藏
pub fn toggle_window_visibility() {
    let mut visible = WINDOW_VISIBLE.lock().unwrap();
    *visible = !*visible;
    
    #[cfg(target_os = "windows")]
    {
        use winapi::um::winuser::{FindWindowW, ShowWindow, SW_HIDE, SW_SHOW, SetForegroundWindow};
        use std::ptr;
        
        unsafe {
            // 查找主窗口 (需要根据实际窗口标题调整)
            let window_title: Vec<u16> = "RustDesk\0".encode_utf16().collect();
            let hwnd = FindWindowW(ptr::null(), window_title.as_ptr());
            
            if !hwnd.is_null() {
                if *visible {
                    ShowWindow(hwnd, SW_SHOW);
                    SetForegroundWindow(hwnd);
                    log::info!("窗口已显示");
                } else {
                    ShowWindow(hwnd, SW_HIDE);
                    log::info!("窗口已隐藏到后台");
                }
            }
        }
    }
}

/// 热键事件处理循环
pub fn start_hotkey_listener() {
    #[cfg(target_os = "windows")]
    {
        std::thread::spawn(|| {
            use global_hotkey::GlobalHotKeyEvent;
            
            let receiver = GlobalHotKeyEvent::receiver();
            log::info!("热键监听线程已启动");
            
            loop {
                if let Ok(_event) = receiver.recv() {
                    log::info!("检测到热键按下 Ctrl+Alt+J");
                    toggle_window_visibility();
                }
            }
        });
    }
}

/// 最小化到系统托盘
pub fn minimize_to_tray() {
    log::info!("最小化到系统托盘");
    let mut visible = WINDOW_VISIBLE.lock().unwrap();
    *visible = false;
    
    #[cfg(target_os = "windows")]
    {
        use winapi::um::winuser::{FindWindowW, ShowWindow, SW_HIDE};
        use std::ptr;
        
        unsafe {
            let window_title: Vec<u16> = "RustDesk\0".encode_utf16().collect();
            let hwnd = FindWindowW(ptr::null(), window_title.as_ptr());
            
            if !hwnd.is_null() {
                ShowWindow(hwnd, SW_HIDE);
            }
        }
    }
}
