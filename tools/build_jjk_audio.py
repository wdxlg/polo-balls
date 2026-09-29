"""咒术回战 音频第三轮（2026-09-29）：日语原声 + 动画/Mixkit 音效，叠混后输出 OGG。

项目根目录运行： python tools/build_jjk_audio.py [--ffmpeg PATH] [--fetch]
* 原始文件逐字节保存在 sources/jjk/audio_r3/（.gdignore），缺失且带 --fetch 时从 URL 重新下载
  （YouTube 源需 yt-dlp）。
* 每个输出 = 若干层 (源, 起点, 时长, 延迟, 增益) 叠混 → 淡入淡出 → loudnorm I=-16 → Vorbis q6。
* 结果合并写入 audio/characters/咒术回战/SOURCE.json 的 "sounds"（覆盖同名键，其它键保留）。
语音全部为日语（动画/游戏原声）；「龍鱗・反発・番いの流星」咏唱没有任何官方日语配音，世界斩改用官方「解」。
Rights: 动画音频版权归原作者（© 芥見下々/集英社/MAPPA）；Mixkit 音效按 Mixkit Free License。仅本地同人项目使用。
"""
import argparse, hashlib, json, os, re, subprocess, urllib.request

RAW = "sources/jjk/audio_r3"
SND = "audio/characters/咒术回战"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36"

MI = 'https://www.myinstants.com/media/sounds/'
YT = 'https://www.youtube.com/watch?v='
MK = 'https://assets.mixkit.co/active_storage/sfx/{0}/{0}-preview.mp3'

SRC = {
    # --- 日语语音（动画/游戏原声） ---
    'otKdt4L4DOk.mp3': (YT + 'otKdt4L4DOk', 'TV 动画 呪術廻戦 第20话 五条悟「術式順転『蒼』」'),
    'KB_y-lYj_b4.mp3': (YT + 'KB_y-lYj_b4', 'TV 动画 渋谷事変 伏黒恵「八握剣 異戒神将 魔虚羅」'),
    'tLCYm3LkIgU.mp3': (YT + 'tLCYm3LkIgU', 'TV 动画 渋谷事変 第42话 BD 宿儺「■（フーガ）」'),
    'tmpfzpjrfx9.mp3': (MI + 'tmpfzpjrfx9.mp3', 'myinstants: 宿儺「身の程を弁えろ… 痴れ者が」'),
    'sukuna-kai.mp3': (MI + 'sukuna-kai.mp3', 'myinstants: 宿儺「解」'),
    'kokusen.mp3': (MI + 'kokusen.mp3', 'myinstants: 「黒閃」'),
    # --- 动画音效 ---
    'mahito-black-flash-effect-season-2-episode-20.mp3': (MI + 'mahito-black-flash-effect-season-2-episode-20.mp3', 'myinstants: 动画 渋谷事変 黑闪命中音效'),
    'sukuna-slash.mp3': (MI + 'sukuna-slash.mp3', 'myinstants: 动画 宿儺斬撃音'),
    'sukuna-slash2.mp3': (MI + 'sukuna-slash2.mp3', 'myinstants: 动画 宿儺斬撃音 2'),
    # --- Mixkit 免费音效（Mixkit Free License） ---
    **{f'{i}.mp3': (MK.format(i), f'Mixkit #{i} {n}') for i, n in [
        (2599, 'Heavy electric shockwave impact'), (2782, 'Epic impact afar explosion'),
        (3114, 'Fast sci fi transition sweep'), (772, 'Quick zoom impact'),
        (2158, 'Quick saber cut'), (2763, 'Sword slashes in battle'), (2796, 'Sword gore slash hit'),
        (2795, 'Heavy sword smashes metal'), (1143, 'Cinematic whoosh deep impact'),
        (1343, 'Fire explosion'), (1972, 'Giant monster roar'), (14, 'Aggressive monster beast roar'),
        (1286, 'Cinematic impact thunder'), (1508, 'Lightning whip')]},
}

R = {
    # 语音（全部日语）
    'gojo_blue': dict(layers=[('otKdt4L4DOk.mp3', 5.35, 2.6, 0, 0)], fo=0.3, lang='ja', use='术式顺转·苍（日语原声）'),
    'sukuna_intro': dict(layers=[('tmpfzpjrfx9.mp3', 0.25, 4.9, 0, 0)], fo=0.3, lang='ja', use='宿傩登场：身の程を弁えろ… 痴れ者が'),
    'sukuna_kai': dict(layers=[('sukuna-kai.mp3', 0.25, 0.95, 0, 0)], fo=0.15, lang='ja', use='解（蛛网/强化解时的语音）'),
    'sukuna_fuga': dict(layers=[('tLCYm3LkIgU.mp3', 5.8, 4.4, 0, 0)], fo=0.8, lang='ja', use='■（フーガ）语音+火矢拉弓（动画原声）'),
    'mahoraga_summon': dict(layers=[('KB_y-lYj_b4.mp3', 25.85, 6.9, 0, 0)], fo=0.5, lang='ja', use='召唤：八握剣 異戒神将 魔虚羅（日语原声）'),
    'black_flash': dict(layers=[('kokusen.mp3', 0.0, 3.0, 0, 0)], fo=0.3, lang='ja', use='黑闪 语音「黒閃」（动画原声）'),
    'sukuna_world_slash': dict(layers=[
        ('sukuna-kai.mp3', 0.25, 0.95, 0.0, 0),
        ('2795.mp3', 0.0, 1.4, 0.30, -2),
        ('1143.mp3', 0.15, 2.0, 0.25, -1),
        ('2599.mp3', 3.55, 2.8, 0.38, -3)], fo=0.6, lang='ja', use='世界斩发动：解 + 断空斩击（咏唱无官方日语配音，改为官方「解」）'),
    # 音效
    'black_flash_hit': dict(layers=[('mahito-black-flash-effect-season-2-episode-20.mp3', 0.0, 1.5, 0, 0), ('772.mp3', 0.1, 0.6, 0.0, -8)], fo=0.3, lang='', use='黑闪命中音效（动画）'),
    'sukuna_world_slash_charge': dict(layers=[('2599.mp3', 2.1, 1.38, 0, 0)], fi=0.05, fo=0.08, lang='', use='世界斩咏唱蓄力（1.2 秒）'),
    'sukuna_fuga_boom': dict(layers=[('1343.mp3', 1.1, 2.8, 0, 0), ('2782.mp3', 0.0, 2.6, 0.0, -9)], fo=0.8, lang='', use='火矢命中爆炸'),
    'sukuna_dismantle': dict(layers=[('sukuna-slash.mp3', 0.0, 1.0, 0, 0), ('2158.mp3', 0.0, 0.6, 0.0, -7)], fo=0.25, lang='', use='解 斩击（动画斩击音）'),
    'sukuna_cleave': dict(layers=[('sukuna-slash2.mp3', 0.0, 0.75, 0, 0), ('2763.mp3', 0.0, 0.9, 0.05, -3), ('2796.mp3', 0.05, 1.0, 0.14, -5)], fo=0.3, lang='', use='捌 连斩'),
    'gojo_purple_sfx': dict(layers=[('2599.mp3', 3.5, 2.9, 0, 0), ('2782.mp3', 0.0, 3.0, 0.05, -7)], fo=0.8, lang='', use='茈 发射冲击'),
    'gojo_teleport': dict(layers=[('3114.mp3', 0.05, 0.65, 0, 0)], fo=0.15, post_gain=9, lang='', use='瞬移'),
    'mahoraga_roar': dict(layers=[('1972.mp3', 0.0, 3.1, 0, 0)], fo=0.6, lang='', use='魔虚罗咆哮'),
    'agito_roar': dict(layers=[('14.mp3', 0.0, 3.0, 0, 0)], fo=0.5, lang='', use='嵌合暗兽 阿吉托 咆哮'),
    'agito_thunder': dict(layers=[('1508.mp3', 0.0, 0.8, 0, -2), ('1286.mp3', 0.35, 2.4, 0.04, 0)], fo=0.6, lang='', use='鵺 落雷'),
}



def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def seconds(ff, p):
    err = subprocess.run([ff, "-hide_banner", "-i", p], capture_output=True, text=True, errors="replace").stderr
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", err)
    return round(int(m[1]) * 3600 + int(m[2]) * 60 + float(m[3]), 2) if m else 0.0


def fetch(name, url):
    path = os.path.join(RAW, name)
    if "youtube.com" in url:
        subprocess.run(["yt-dlp", "-f", "bestaudio", "-x", "--audio-format", "mp3", "-o", path[:-4] + ".%(ext)s", url], check=True)
    else:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        open(path, "wb").write(urllib.request.urlopen(req, timeout=60).read())


def build(ff, key, r):
    layers = r["layers"]
    total = max(d + t for _, _, t, d, _ in layers)
    fi = r.get("fi", 0.02); fo = r["fo"]
    args = [ff, "-y", "-hide_banner", "-loglevel", "error"]
    parts = []
    for i, (src, ss, t, d, g) in enumerate(layers):
        args += ["-ss", str(ss), "-t", str(t), "-i", os.path.join(RAW, src)]
        ms = int(d * 1000)
        parts.append("[%d:a]aresample=44100,aformat=channel_layouts=stereo,volume=%sdB,adelay=%d|%d,apad=whole_dur=%s[l%d]" % (i, g, ms, ms, total, i))
    post = "afade=t=in:d=%s,afade=t=out:st=%.3f:d=%s,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100" % (fi, total - fo, fo)
    if r.get("post_gain"): post += ",volume=%sdB,alimiter=limit=0.84" % r["post_gain"]
    if len(layers) > 1:
        fc = ";".join(parts) + ";" + "".join("[l%d]" % i for i in range(len(layers))) + "amix=inputs=%d:normalize=0:duration=longest,%s[o]" % (len(layers), post)
    else:
        fc = parts[0] + ";[l0]" + post + "[o]"
    out = os.path.join(SND, key + ".ogg")
    args += ["-filter_complex", fc, "-map", "[o]", "-t", "%.3f" % total, "-c:a", "libvorbis", "-q:a", "6", out]
    subprocess.run(args, check=True)
    return out, total, post


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--ffmpeg", default=os.environ.get("FFMPEG", "ffmpeg"))
    ap.add_argument("--fetch", action="store_true")
    a = ap.parse_args(argv)
    os.makedirs(RAW, exist_ok=True)
    for name, (url, _) in SRC.items():
        if not os.path.exists(os.path.join(RAW, name)):
            if not a.fetch: raise SystemExit("missing raw %s (use --fetch)" % name)
            fetch(name, url)
    src_json = os.path.join(SND, "SOURCE.json")
    record = json.load(open(src_json, encoding="utf8")) if os.path.exists(src_json) else {"sounds": {}}
    for key, r in R.items():
        out, total, post = build(a.ffmpeg, key, r)
        layers = []
        for src, ss, t, d, g in r["layers"]:
            url, desc = SRC[src]
            p = os.path.join(RAW, src)
            layers.append({"download": url, "desc": desc, "raw": RAW + "/" + src, "raw_sha256": sha(p), "raw_seconds": seconds(a.ffmpeg, p),
                           "trim_start": ss, "trim_seconds": t, "delay": d, "gain_db": g})
        record["sounds"][key] = {"layers": layers, "seconds": round(total, 2), "filters": post, "output": out.replace("\\", "/"),
                                 "output_sha256": sha(out), "language": r["lang"] or "none (sfx)", "use": r["use"], "round": "r3 2026-09-29"}
        print("sound", key, round(total, 2), "s")
    json.dump(record, open(src_json, "w", encoding="utf8"), ensure_ascii=False, indent=1)
    print("OK", len(R), "sounds (r3)")


if __name__ == "__main__":
    main()
