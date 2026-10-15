// 客户端心跳：每 60 秒向管理后台上报设备在线状态
// 管理后台据此判定设备是否真实在线（客户端退出后停止心跳 → 面板标记离线）
// 同时接收设备授权状态：管理后台可将设备设置到期时间（expires_at），
// 到期设备心跳响应 authorized=false → 停止被控服务（stop-service=Y），
// RendezvousMediator 检测到该选项后停止向服务器注册并断开现有连接，
// 设备将无法被远程连接；管理员改回永久/延长后自动恢复。
use hbb_common::config::{Config, LocalConfig};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

/// 学员编号导入（下载页定制流程）：下载页按编号命名安装包
/// （888-<编号>-setup.exe），安装器安装时把编号写入注册表；
/// 客户端启动时导入到配置（全局+本地双写）并删除注册表值——
/// 一次性导入：此后用户在客户端内的手动修改不会被安装覆盖。
#[cfg(windows)]
pub fn import_student_no_from_registry() {
    use winreg::enums::*;
    use winreg::RegKey;
    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let Ok(key) = hklm.open_subkey(r"Software\888") else {
        return;
    };
    // 导入标记：安装器每次安装写当前时间戳（StudentNoMark）。
    // 与配置侧记录的上次导入标记对比：
    // - 不同 = 新的安装事件（第二次下载换了编号）→ 覆盖导入新编号，
    //   客户端与后台同步更新为最新编号；
    // - 相同或无标记 = 同一安装包已导入过 → 跳过（HKLM 残留普通用户
    //   删不掉，靠标记幂等，不会覆盖用户在客户端手动输入的编号）。
    // （不能只判断"配置已有编号就跳过"——那会挡住换编号重装场景）
    let Ok(mark) = key.get_value::<String, _>("StudentNoMark") else {
        return;
    };
    if mark.is_empty() || Config::get_option("student-no-mark") == mark {
        return;
    }
    let Ok(no) = key.get_value::<String, _>("StudentNo") else {
        return;
    };
    let no = no.trim().to_string();
    if no.is_empty() {
        return;
    }
    // 覆盖导入：双写全局+本地配置（与界面读取/心跳上报配对），
    // 并记录已导入标记（幂等依据），随后立即触发一次上报
    Config::set_option("student-no".into(), no.clone());
    LocalConfig::set_option("student-no".into(), no.clone());
    Config::set_option("student-no-mark".into(), mark);
    hbb_common::log::info!("已从安装包导入学员编号: {}", no);
    // 尝试删除注册表值（一次性导入）；普通用户无写权限删不掉也无妨，
    // 上面的标记对比已保证不会重复导入
    if let Ok(wkey) = hklm.open_subkey_with_flags(r"Software\888", KEY_WRITE) {
        let _ = wkey.delete_value("StudentNo");
        let _ = wkey.delete_value("StudentNoMark");
    }
    thread::spawn(|| {
        thread::sleep(Duration::from_secs(3));
        let _ = send_heartbeat();
    });
}

const HEARTBEAT_INTERVAL_SECS: u64 = 60;

// 保存学员编号等场景需要立即上报（不等下一轮 60 秒心跳）
static TRIGGER_NOW: AtomicBool = AtomicBool::new(false);

pub fn start() {
    thread::spawn(|| loop {
        if let Err(e) = send_heartbeat() {
            // 生产构建不落盘日志，仅调试模式可见
            hbb_common::log::info!("Heartbeat: {}", e);
        }
        // 正常等 60 秒；期间被 trigger_now() 置位则立即进入下一轮上报
        for _ in 0..HEARTBEAT_INTERVAL_SECS {
            if TRIGGER_NOW.swap(false, Ordering::SeqCst) {
                break;
            }
            thread::sleep(Duration::from_secs(1));
        }
    });
}

/// 主界面保存学员编号后调用：立即触发一次上报，后台马上可见
pub fn trigger_now() {
    TRIGGER_NOW.store(true, Ordering::SeqCst);
}

/// 读取当前学员编号（**跨进程安全**）。
///
/// 问题背景：学员编号在**用户会话进程**（主界面/托盘）里写入，而心跳在
/// **被控服务进程**（SYSTEM）里发。RustDesk 的 Config 在进程内是静态缓存
/// （CONFIG2 lazy_static），**进程启动后不会自动重载**——服务进程先启动、
/// 用户随后在界面改编号时，服务进程内存里仍是旧值（通常为空），
/// 心跳上报的 student_no 一直是空，后台永远看不到编号。
/// （实测：安装时自动导入的编号能上报，界面手动改的不能。）
///
/// 方案：每次心跳**直接读共享配置文件**（RustDesk 已把 SYSTEM 的
/// systemprofile 路径重定向到 ServiceProfiles\LocalService，服务与用户
/// 会话共享同一份配置），内存值仅作读文件失败时的兜底。
fn read_student_no() -> String {
    if let Ok(s) = std::fs::read_to_string(Config::file()) {
        for line in s.lines() {
            let line = line.trim();
            let Some(rest) = line.strip_prefix("student-no") else {
                continue;
            };
            let Some(v) = rest.trim_start().strip_prefix('=') else {
                continue;
            };
            let v = v.trim().trim_matches('"').trim_matches('\'').trim();
            if !v.is_empty() {
                return v.to_string();
            }
        }
    }
    // 兜底：进程内缓存（全局优先，空则本地）
    let global = Config::get_option("student-no");
    if global.is_empty() {
        LocalConfig::get_option("student-no")
    } else {
        global
    }
}

/// 主界面保存学员编号后调用：立即向后台上报一次。
/// 不能只靠 TRIGGER_NOW 标志（进程内 static，界面进程设置后服务进程
/// 心跳线程看不到），所以直接发一次上报请求，用户点保存后后台即时可见。
pub fn report_now() {
    thread::spawn(|| {
        thread::sleep(Duration::from_millis(500));
        if let Err(e) = send_heartbeat() {
            hbb_common::log::info!("立即上报失败: {}", e);
        }
    });
}

fn send_heartbeat() -> hbb_common::ResultType<()> {
    let api = crate::common::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server")
    );
    if api.is_empty() {
        return Ok(());
    }
    let url = format!("{}/api/devices/register", api.trim_end_matches('/'));
    // 只上报 device_id + 学员编号（用户在客户端自行输入），
    // 不覆盖管理后台/同步脚本设置的设备名称。
    let student_no = read_student_no();
    let body = serde_json::json!({
        "device_id": Config::get_id(),
        "student_no": student_no,
        // 是否注册到 hbbs（RendezvousMediator 收到注册响应）：
        // 仅作诊断参考，**不参与在线判定**——内网直连/NAT 打洞成功的设备
        // 不经 hbbs 也能被远程，但此标志为 0，误判为离线。
        "registered": crate::rendezvous_mediator::REGISTER_PEER_OK
            .load(std::sync::atomic::Ordering::SeqCst),
        // 到期停被控标记：被控服务进程仍在运行（心跳照发），但已停止
        // 注册 hbbs（stop-service=Y），远程连不上——后台据此判离线。
        "expired": is_device_expired(),
    });
    let client = crate::hbbs_http::create_http_client_with_url(&url);
    let resp = client
        .post(&url)
        .json(&body)
        .timeout(Duration::from_secs(10))
        .send()?;
    if !resp.status().is_success() {
        hbb_common::bail!("HTTP {}", resp.status());
    }
    // 设备授权检查：服务器未返回该字段时保持现状（兼容旧版管理后台）
    let authorized = resp
        .json::<serde_json::Value>()
        .ok()
        .and_then(|v| v.get("authorized").and_then(|a| a.as_bool()))
        .unwrap_or(true);
    apply_device_authorization(authorized);
    Ok(())
}

/// 设备是否已被后台置为到期（stop-service=Y）
/// 供心跳上报：到期后被控服务进程仍在运行但已停止注册 hbbs，
/// 后台需要据此判离线（远程确实连不上）。
fn is_device_expired() -> bool {
    Config::get_option("stop-service") == "Y" || LocalConfig::get_option("stop-service") == "Y"
}

/// 根据授权状态启停被控服务。
/// 被控服务进程（--service）内生效：更新 stop-service 选项并重启 RendezvousMediator，
/// 到期 → 停止注册 + 断开现有连接（无法被远程连接），恢复授权 → 重新注册。
/// 其他进程（主窗口/托盘）中调用安全：仅更新本地配置（落盘），标志位操作无副作用，
/// 被控服务进程自身的心跳线程也会做同样处理。
fn apply_device_authorization(authorized: bool) {
    let stopped = Config::get_option("stop-service") == "Y";
    if !authorized && !stopped {
        hbb_common::log::info!("Device expired, stopping controlled service");
        Config::set_option("stop-service".into(), "Y".into());
        crate::rendezvous_mediator::RendezvousMediator::restart();
    } else if authorized && stopped {
        hbb_common::log::info!("Device re-authorized, restarting controlled service");
        Config::set_option("stop-service".into(), "".into());
        crate::rendezvous_mediator::RendezvousMediator::restart();
    }
}
