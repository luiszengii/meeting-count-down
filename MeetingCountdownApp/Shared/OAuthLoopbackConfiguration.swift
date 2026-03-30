import Foundation

/// `OAuthLoopbackConfiguration` 固定描述本地 OAuth 回调监听地址。
/// 这个类型在 Phase 0 的意义不是立即起 HTTP 服务，而是先把“回调地址是什么”
/// 从文档约定提升为代码约定，避免后续真正实现 `OAuthLoopbackServer` 时，
/// 不同模块各自写一份 `127.0.0.1:23388/oauth/callback` 字符串。
struct OAuthLoopbackConfiguration: Equatable, Sendable {
    /// 本地回环地址只允许当前机器访问，避免把 OAuth 回调暴露到局域网。
    let host: String
    /// 固定端口供飞书开放平台登记和本地诊断检查复用。
    let port: Int
    /// 回调路径固定为 `/oauth/callback`，后续 loopback server 只需监听这一路径。
    let callbackPath: String

    /// 统一生成给 OAuth 授权请求和平台配置共用的完整回调地址。
    var callbackURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = callbackPath

        guard let url = components.url else {
            preconditionFailure("OAuth loopback callback URL must always be valid")
        }

        return url
    }

    /// 目前项目约定的飞书 OAuth loopback 固定地址。
    static let feishuDefault = OAuthLoopbackConfiguration(
        host: "127.0.0.1",
        port: 23388,
        callbackPath: "/oauth/callback"
    )
}
