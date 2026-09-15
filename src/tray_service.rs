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
    #[cfg(target_os = "windows")]
    {
        use winapi::um::winuser::{
            FindWindowW, GetForegroundWindow, IsIconic, IsWindowVisible, ShowWindow, SW_HIDE,
            SW_RESTORE, SW_SHOW,
        };
        use std::ptr;

        unsafe {
            // 动态获取应用名称作为窗口标题
            let app_name = crate::common::get_app_name();
            let window_title: Vec<u16> = format!("{}\0", app_name).encode_utf16().collect();
            let hwnd = FindWindowW(ptr::null(), window_title.as_ptr());

            if hwnd.is_null() {
                // 主窗口进程尚未启动，直接启动带界面的主窗口进程
                log::warn!("未找到主窗口 (标题: {})，启动主窗口进程", app_name);
                let _ = crate::run_me(Vec::<&std::ffi::OsStr>::new());
                *WINDOW_VISIBLE.lock().unwrap() = true;
                return;
            }

            // 依据窗口真实状态判断，而不是靠标志位：
            // 用户手动关闭窗口后标志位仍为"可见"，若盲目取反会执行隐藏，
            // 表现为"程序在后台时按热键唤不出主窗口"。
            let is_visible = IsWindowVisible(hwnd) != 0;
            let is_iconic = IsIconic(hwnd) != 0;
            // 只有"可见 + 未最小化 + 已在最前"时才隐藏；
            // 被其它窗口挡住时按热键应提到最前，而不是被隐藏。
            let is_foreground = GetForegroundWindow() == hwnd;
            if is_visible && !is_iconic && is_foreground {
                ShowWindow(hwnd, SW_HIDE);
                *WINDOW_VISIBLE.lock().unwrap() = false;
                log::info!("主窗口已隐藏到后台");
            } else {
                ShowWindow(hwnd, SW_SHOW);
                ShowWindow(hwnd, SW_RESTORE);
                bring_window_to_foreground(hwnd);
                *WINDOW_VISIBLE.lock().unwrap() = true;
                log::info!("主窗口已显示并置于前台");
            }
        }
    }
}

/// 可靠地把窗口提到最前
///
/// 后台进程直接调用 SetForegroundWindow 会被 Windows 的前台锁定机制拦下
/// （窗口只会闪一下或在其它窗口后面），这里做两层处理：
/// 1. 模拟一次 Alt 键按下/抬起，让系统认为用户刚有键盘操作（经典解锁技巧）
/// 2. 借用前台线程的输入队列（AttachThreadInput）绕过限制
#[cfg(target_os = "windows")]
unsafe fn bring_window_to_foreground(hwnd: winapi::shared::windef::HWND) {
    use winapi::um::winuser::{
        AttachThreadInput, GetForegroundWindow, GetWindowThreadProcessId, SetForegroundWindow,
        keybd_event,
    };
    use std::ptr;

    const VK_MENU: u8 = 0x12;
    const KEYEVENTF_KEYUP: u32 = 0x0002;
    keybd_event(VK_MENU, 0, 0, 0);
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);

    let fg = GetForegroundWindow();
    if !fg.is_null() {
        let fg_thread = GetWindowThreadProcessId(fg, ptr::null_mut());
        let target_thread = GetWindowThreadProcessId(hwnd, ptr::null_mut());
        if fg_thread != target_thread {
            AttachThreadInput(target_thread, fg_thread, 1);
            SetForegroundWindow(hwnd);
            AttachThreadInput(target_thread, fg_thread, 0);
            return;
        }
    }
    SetForegroundWindow(hwnd);
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
            let app_name = crate::common::get_app_name();
            let window_title: Vec<u16> = format!("{}\0", app_name).encode_utf16().collect();
            let hwnd = FindWindowW(ptr::null(), window_title.as_ptr());
            
            if !hwnd.is_null() {
                ShowWindow(hwnd, SW_HIDE);
                log::info!("窗口已隐藏 (标题: {})", app_name);
            } else {
                log::warn!("未找到要隐藏的窗口 (标题: {})", app_name);
            }
        }
    }
}
