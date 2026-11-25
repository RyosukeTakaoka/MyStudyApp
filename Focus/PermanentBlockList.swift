import Foundation

// 常時ブロック(365日24時間)の「どのサイトを止めるか」の決まり。
// スクリーンタイムに頼らない計算だけにしてあるので、テストできる(実際に止めるのは PermanentBlock.swift)。
enum PermanentBlockList {
    /// ニコニコ動画を止め始める日
    static let niconicoStartDay = "2027-01-01"

    /// スクリーンタイムの「止めるサイト」に入れられる数の上限
    static let maxDomains = 50

    static let youtube = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "youtube-nocookie.com", "www.youtube-nocookie.com"]
    static let x = ["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]
    static let instagram = ["instagram.com", "www.instagram.com"]
    static let tiktok = ["tiktok.com", "www.tiktok.com", "m.tiktok.com", "vt.tiktok.com", "vm.tiktok.com"]
    static let niconico = ["nicovideo.jp", "www.nicovideo.jp", "sp.nicovideo.jp", "nico.ms"]

    /// Invidious(YouTube の代わりのサイト)のよく知られた公開ホスト。
    /// 公式の説明書(docs.invidious.io)に今のっているものを先に。最新の一覧(api.invidious.io)のあとに足す
    static let invidiousFallback = [
        "inv.nadeko.net", "invidious.nerdvpn.de", "yt.chocolatemoo53.com", "invidious.tiekoetter.com",
        "yewtu.be", "invidious.flokinet.to", "invidious.adminforge.de", "iv.melmac.space", "invidious.private.coffee",
        "inv.vern.cc", "invidious.reallyaweso.me", "invidious.dhusch.de", "invidious.0011.lt",
        "iv.ggtyler.dev", "invidious.jing.rocks",
        "inv.tux.pizza", "invidious.privacyredirect.com", "invidious.protokolla.fi", "yt.artemislena.eu",
        "invidious.f5.si", "iv.datura.network", "invidious.perennialte.ch", "invidious.einfachzocken.eu",
        "inv.in.projectsegfau.lt", "invidious.drgns.space", "invidious.materialio.us", "invidious.fdn.fr",
        "vid.puffyan.us", "invidious.lunar.icu", "invidious.privacydev.net", "inv.zzls.xyz", "yt.cdaut.de",
        "invidious.slipfox.xyz", "invidious.io",
    ]

    /// その日に止めるサイト(上限 50 件)。入れる順番:
    ///   1. 決まったサイト(YouTube・X・Instagram・TikTok、1/1 からニコニコ)
    ///   2. 自分で足したサイト(custom)
    ///   3. Invidious(最新の一覧 → よく知られたホスト)
    static func domains(today: String, invidious: [String], custom: [String] = []) -> [String] {
        var list = youtube + x + instagram + tiktok
        if today >= niconicoStartDay {
            list += niconico
        }
        for host in (custom + invidious + invidiousFallback).map(normalize) where !host.isEmpty && !list.contains(host) {
            guard list.count < maxDomains else { break }
            list.append(host)
        }
        return Array(list.prefix(maxDomains))
    }

    /// 自分で足すサイトの入力を、ホストの形にする。おかしな入力なら nil
    static func customHost(from input: String) -> String? {
        let host = normalize(input)
        guard host.contains("."), !host.contains(" "),
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return host
    }

    /// "https://Yewtu.be/" → "yewtu.be"
    static func normalize(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = h.range(of: "://") { h = String(h[range.upperBound...]) }
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        return h
    }

    /// api.invidious.io/instances.json の中身から、ふつうの Web(https)で開けるホストを取り出す。
    /// 形: [["yewtu.be", {"type": "https", ...}], ["xxx.onion", {"type": "onion", ...}], ...]
    static func parseInvidiousInstances(_ data: Data) -> [String] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return rows.compactMap { row -> String? in
            guard row.count >= 2, let host = row[0] as? String,
                  let info = row[1] as? [String: Any], (info["type"] as? String) == "https"
            else { return nil }
            let normalized = normalize(host)
            return normalized.isEmpty ? nil : normalized
        }
    }

    /// 1月1日になった瞬間にニコニコ動画を止めるための、監視の名前(拡張機能がこの名前を見て止める)
    static let niconicoActivityName = "permanent.niconico"
}
