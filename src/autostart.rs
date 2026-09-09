// 开机自启动功能模块
#![cfg(target_os = "windows")]

use hbb_common::log;
use std::path::PathBuf;

#[cfg(target_os = "windows")]
use winreg::enums::*;
#[cfg(target_os = "windows")]
use winreg::RegKey;

const APP_NAME: &str = "RustDesk";

/// 设置开机自启动
pub fn enable_autostart() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "windows")]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let path = r"Software\Microsoft\Windows\CurrentVersion\Run";
        let (key, _) = hkcu.create_subkey(path)?;
        
        let exe_path = std::env::current_exe()?;
        let exe_path_str = format!("\"{}\" --tray", exe_path.display());
        
        key.set_value(APP_NAME, &exe_path_str)?;
        
        log::info!("开机自启动已启用: {}", exe_path_str);
        Ok(())
    }
    
    #[cfg(not(target_os = "windows"))]
    {
        log::warn!("当前系统不支持自动设置开机自启动");
        Ok(())
    }
}

/// 禁用开机自启动
pub fn disable_autostart() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "windows")]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let path = r"Software\Microsoft\Windows\CurrentVersion\Run";
        
        if let Ok(key) = hkcu.open_subkey_with_flags(path, KEY_WRITE) {
            let _ = key.delete_value(APP_NAME);
            log::info!("开机自启动已禁用");
        }
        
        Ok(())
    }
    
    #[cfg(not(target_os = "windows"))]
    {
        Ok(())
    }
}

/// 检查是否已启用自启动
pub fn is_autostart_enabled() -> bool {
    #[cfg(target_os = "windows")]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let path = r"Software\Microsoft\Windows\CurrentVersion\Run";
        
        if let Ok(key) = hkcu.open_subkey(path) {
            if let Ok(_value) = key.get_value::<String, _>(APP_NAME) {
                return true;
            }
        }
        false
    }
    
    #[cfg(not(target_os = "windows"))]
    {
        false
    }
}

/// 初始化时自动启用开机自启动
pub fn init_autostart() {
    if !is_autostart_enabled() {
        if let Err(e) = enable_autostart() {
            log::error!("启用开机自启动失败: {}", e);
        } else {
            log::info!("开机自启动已自动启用");
        }
    } else {
        log::info!("开机自启动已存在，无需重复设置");
    }
}
