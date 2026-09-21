// 客户端心跳：每 60 秒向管理后台上报设备在线状态
// 管理后台据此判定设备是否真实在线（客户端退出后停止心跳 → 面板标记离线）
// 同时接收设备授权状态：管理后台可将设备设置到期时间（expires_at），
// 到期设备心跳响应 authorized=false → 停止被控服务（stop-service=Y），
// RendezvousMediator 检测到该选项后停止向服务器注册并断开现有连接，
// 设备将无法被远程连接；管理员改回永久/延长后自动恢复。
use hbb_common::config::Config;
use std::thread;
use std::time::Duration;

const HEARTBEAT_INTERVAL_SECS: u64 = 60;

pub fn start() {
    thread::spawn(|| loop {
        if let Err(e) = send_heartbeat() {
            // 生产构建不落盘日志，仅调试模式可见
            hbb_common::log::info!("Heartbeat: {}", e);
        }
        thread::sleep(Duration::from_secs(HEARTBEAT_INTERVAL_SECS));
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
    // 只上报 device_id，不覆盖管理后台/同步脚本设置的设备名称
    let body = serde_json::json!({ "device_id": Config::get_id() });
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
