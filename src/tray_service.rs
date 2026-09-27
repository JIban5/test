// 系统托盘和热键管理模块
#![cfg(target_os = "windows")]

use hbb_common::log;
use std::sync::{Arc, Mutex};

lazy_static::lazy_static! {
    static ref WINDOW_VISIBLE: Arc<Mutex<bool>> = Arc::new(Mutex::new(true));
}

// RegisterHotKey 参数（自定义常量，避免 winapi 版本差异）
const HOTKEY_ID: i32 = 0xB001;
const MOD_ALT: u32 = 0x0001;
const MOD_CONTROL: u32 = 0x0002;
const VK_J: u32 = 0x4A; // 'J' 键虚拟键码
const WM_HOTKEY: u32 = 0x0312;

/// 启动全局热键监听线程（Ctrl+Alt+J）
///
/// 在本线程内完成 RegisterHotKey + GetMessage 消息泵闭环：
/// RegisterHotKey 的 WM_HOTKEY 消息投递到【注册线程】的消息队列，
/// 因此注册与消息泵必须在同一线程，缺一不可。
/// 之前依赖 global-hotkey 库且主线程 sleep 死循环常驻，
/// 消息无人泵导致热键事件永远无法分发（表现为快捷键完全无效）。
pub fn start_hotkey_listener() {
    #[cfg(target_os = "windows")]
    std::thread::spawn(|| unsafe {
        use winapi::um::winuser::{
            DispatchMessageW, GetMessageW, MSG, RegisterHotKey, TranslateMessage,
        };

        // 注册 Ctrl+Alt+J（同线程注册，消息才会进本线程队列）。
        // 失败常见原因：组合键被其他程序通过 RegisterHotKey 占用，
        // 或升级场景中旧版进程尚未完全退出（持有同一注册），稍等重试。
        let mut registered = false;
        for _ in 0..5 {
            if RegisterHotKey(
                std::ptr::null_mut(),
                HOTKEY_ID,
                MOD_CONTROL | MOD_ALT,
                VK_J,
            ) != 0
            {
                registered = true;
                break;
            }
            log::warn!("注册全局热键失败，2 秒后重试（可能被占用或旧进程尚未退出）");
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        if !registered {
            log::error!("注册全局热键 Ctrl+Alt+J 最终失败，热键不可用");
            return;
        }
        log::info!("全局热键 Ctrl+Alt+J 已注册，监听线程启动");

        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) > 0 {
            if msg.message == WM_HOTKEY && msg.wParam as i32 == HOTKEY_ID {
                log::info!("检测到热键按下 Ctrl+Alt+J");
                toggle_window_visibility();
            }
            TranslateMessage(&mut msg);
            DispatchMessageW(&mut msg);
        }
    });
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

/// 追加一行自删除调试日志（验证用，验证通过后移除）。
/// 独立于 log 框架：无论日志初始化状态如何都必定落盘；失败静默跳过。
/// dir 为 None 时跳过。
fn append_selflog(dir: Option<&std::path::Path>, msg: &str) {
    let dir = match dir {
        Some(d) => d,
        None => return,
    };
    let ts = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    use std::io::Write;
    if std::fs::create_dir_all(dir).is_ok() {
        if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(dir.join("delself.log"))
        {
            let _ = writeln!(f, "[app] ({}) {}", ts, msg);
        }
    }
}

/// 主界面"诊断日志"按钮：立即尝试一次安装包删除，并返回完整日志文本。
/// 与 --tray 启动时的后台兜底共用 %APPDATA%\888\delself.log；
/// 读到记录时同步写安装包同目录（提权账户差异下用户也能看到）。
pub fn run_delself_once_and_collect_log() -> String {
    use winreg::enums::*;
    use winreg::RegKey;

    const SUBKEY: &str = r"Software\888";
    const VALUE_NAME: &str = "DeleteInstallerPath";

    let appdata_dir = std::env::var_os("APPDATA")
        .map(|p| std::path::PathBuf::from(p).join("888"));
    let mut pkg_dir: Option<std::path::PathBuf> = None;
    // 局部宏（不用闭包）：宏在调用点展开，直接引用当前变量，无借用捕获问题
    macro_rules! dlog {
        ($msg:expr) => {{
            let m: String = ($msg).to_string();
            append_selflog(appdata_dir.as_deref(), &m);
            append_selflog(pkg_dir.as_deref(), &m);
        }};
    }

    dlog!("manual trigger from UI");

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let record: Option<String> = hkcu
        .open_subkey(SUBKEY)
        .ok()
        .and_then(|k| k.get_value::<String, _>(VALUE_NAME).ok());

    match record {
        Some(path) => {
            pkg_dir = std::path::Path::new(&path)
                .parent()
                .map(|p| p.to_path_buf());
            let res = std::fs::remove_file(&path);
            match &res {
                Ok(_) => dlog!(format!("manual delete: DELETED ({})", path)),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                    dlog!(format!("manual delete: not found, skip ({})", path))
                }
                Err(e) => dlog!(format!("manual delete: busy ({})", e)),
            }
            if res.is_ok() {
                if let Ok(key) = hkcu.open_subkey_with_flags(SUBKEY, KEY_WRITE) {
                    let _ = key.delete_value(VALUE_NAME);
                }
                dlog!("record cleared after manual delete");
            }
        }
        None => {
            dlog!("no registry record -> nothing to delete");
        }
    }

    match &appdata_dir {
        Some(d) => std::fs::read_to_string(d.join("delself.log"))
            .unwrap_or_else(|_| "（暂无日志内容）".to_string()),
        None => "（无法定位日志目录）".to_string(),
    }
}

/// 安装包自删除兜底（应用侧，时机确定性远高于安装器侧的 cmd 延迟删除）：
/// 安装器安装成功后把安装包完整路径写入 HKCU\Software\888\DeleteInstallerPath，
/// 由 --tray 获锁常驻进程在本函数的后台线程里处理：
/// - 无记录           → 直接跳过（非安装场景 / 无升级）
/// - 文件已不存在     → 跳过并清除记录（安装器 cmd 已删或用户已手动清理）
/// - 删除成功         → 清除记录
/// - 文件被占用       → 重试若干次（等安装器退出 / 杀软扫描解锁），
///                      耗尽则保留记录，下次 --tray 启动（含开机自启）再试，
///                      直到删除为止
pub fn delete_pending_installer_async() {
    std::thread::spawn(|| {
        use winreg::enums::*;
        use winreg::RegKey;

        // 调试日志双路径：本账户 %APPDATA%\888\（固定可写）+
        // 安装包同目录（读到记录后设置；提权账户差异下用户看得到）
        let appdata_dir = std::env::var_os("APPDATA").map(|p| std::path::PathBuf::from(p).join("888"));
        let pkg_dir: Option<std::path::PathBuf> = None;
        let dbg = |msg: &str, pkg_dir: &Option<std::path::PathBuf>| {
            append_selflog(appdata_dir.as_deref(), msg);
            append_selflog(pkg_dir.as_deref(), msg);
        };

        dbg(
            &format!(
                "task started, exe={:?}, pid={}",
                std::env::current_exe(),
                std::process::id()
            ),
            &pkg_dir,
        );

        const SUBKEY: &str = r"Software\888";
        const VALUE_NAME: &str = "DeleteInstallerPath";

        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        // 读记录：键或值不存在 → 非安装升级场景，直接跳过
        let installer_path: String = match hkcu.open_subkey(SUBKEY) {
            Ok(key) => match key.get_value::<String, _>(VALUE_NAME) {
                Ok(path) => {
                    dbg(&format!("registry read OK: {}", path), &pkg_dir);
                    path
                }
                Err(e) => {
                    dbg(&format!("registry value read FAILED: {} -> skip", e), &pkg_dir);
                    log::info!("未读取到安装包路径记录，跳过自删除");
                    return;
                }
            },
            Err(e) => {
                dbg(&format!("registry key open FAILED: {} -> skip", e), &pkg_dir);
                log::info!("未读取到安装包路径记录，跳过自删除");
                return;
            }
        };

        // 读到安装包路径后，日志同步写安装包同目录
        let pkg_dir = std::path::Path::new(&installer_path)
            .parent()
            .map(|p| p.to_path_buf());

        // 先等安装器进程退出（毫秒级）+ 杀软对新生 exe 的扫描锁定窗口（数秒）；
        // 本进程常驻，延迟删除不影响热键/主窗口等功能
        dbg("waiting 30s for installer exit / av unlock", &pkg_dir);
        std::thread::sleep(std::time::Duration::from_secs(30));

        let mut done = false;
        for attempt in 1..=10 {
            match std::fs::remove_file(&installer_path) {
                Ok(_) => {
                    dbg(&format!("attempt {}: DELETED", attempt), &pkg_dir);
                    log::info!("安装包已删除: {}", installer_path);
                    done = true;
                    break;
                }
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                    // 文件不存在：跳过即可，视为处理完成
                    dbg("file not found -> skip", &pkg_dir);
                    log::info!("安装包已不存在，无需删除: {}", installer_path);
                    done = true;
                    break;
                }
                Err(e) => {
                    dbg(&format!("attempt {}: busy ({})", attempt, e), &pkg_dir);
                    log::info!("安装包暂时无法删除（第 {} 次）: {}，稍后重试", attempt, e);
                    std::thread::sleep(std::time::Duration::from_secs(6));
                }
            }
        }

        // 确认"已删除/本就不存在"才清记录；长期被占用则保留记录，
        // 下次启动再试，保证最终一定删除
        if done {
            let cleared = match hkcu.open_subkey_with_flags(SUBKEY, KEY_WRITE) {
                Ok(key) => key.delete_value(VALUE_NAME).is_ok(),
                Err(_) => false,
            };
            dbg(&format!("done, record cleared: {}", cleared), &pkg_dir);
        } else {
            dbg("all attempts busy, record kept for next start", &pkg_dir);
        }
    });
}
